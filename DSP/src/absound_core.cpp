/*
 * Absound DSP core implementation. See absound_core.h.
 *
 * Single translation unit (M-Layers): N-track synthesis, FX and the sequencer
 * live together. Tracks come from a fixed preallocated pool so adding/removing a
 * layer from the UI thread never allocates on the audio thread.
 *
 * Real-time rules in ab_core_render(): no heap allocation, no locks, no
 * exceptions. UI-thread parameter writes are scalar/atomic — a known
 * simplification that is safe for our field sizes on the platforms we target.
 */
#include "absound_core.h"

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <new>

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kTwoPi = 6.283185307179586;

inline double midiToHz(double note) { return 440.0 * std::pow(2.0, (note - 69.0) / 12.0); }
inline float clampf(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }
inline float flushDenorm(float x) { return std::fabs(x) < 1.0e-20f ? 0.0f : x; }

struct Noise {
    uint32_t state = 0x1234567u;
    inline float next() {
        state = state * 1664525u + 1013904223u;
        return static_cast<float>(static_cast<int32_t>(state)) * (1.0f / 2147483648.0f);
    }
};

enum class Wave { Saw, Square, Triangle, Sine };

struct Oscillator {
    double phase = 0.0, inc = 0.0, triState = 0.0;
    Wave wave = Wave::Saw;
    void setFreq(double hz, double sr) { inc = hz / sr; }
    static double polyBlep(double t, double dt) {
        if (t < dt) { t /= dt; return t + t - t * t - 1.0; }
        if (t > 1.0 - dt) { t = (t - 1.0) / dt; return t * t + t + t + 1.0; }
        return 0.0;
    }
    float next() {
        const double t = phase, dt = inc;
        double v = 0.0;
        switch (wave) {
            case Wave::Saw: v = 2.0 * t - 1.0; v -= polyBlep(t, dt); break;
            case Wave::Square: {
                v = t < 0.5 ? 1.0 : -1.0;
                v += polyBlep(t, dt);
                double t2 = t + 0.5; if (t2 >= 1.0) t2 -= 1.0;
                v -= polyBlep(t2, dt);
                break;
            }
            case Wave::Triangle: {
                double sq = t < 0.5 ? 1.0 : -1.0;
                sq += polyBlep(t, dt);
                double t2 = t + 0.5; if (t2 >= 1.0) t2 -= 1.0;
                sq -= polyBlep(t2, dt);
                triState = dt * sq + (1.0 - dt) * triState;
                v = triState * 4.0;
                break;
            }
            case Wave::Sine: v = std::sin(t * kTwoPi); break;
        }
        phase += inc; if (phase >= 1.0) phase -= 1.0;
        return static_cast<float>(v);
    }
};

struct ADSR {
    enum class Stage { Idle, Attack, Decay, Sustain, Release };
    Stage stage = Stage::Idle;
    float value = 0.0f, sr = 44100.0f, aRate = 0, dRate = 0, rRate = 0, sustain = 0.7f;
    void configure(float sampleRate, float a, float d, float s, float r) {
        sr = sampleRate;
        aRate = 1.0f / (std::fmax(a, 1.0e-4f) * sr);
        dRate = 1.0f / (std::fmax(d, 1.0e-4f) * sr);
        rRate = 1.0f / (std::fmax(r, 1.0e-4f) * sr);
        sustain = s;
    }
    void gateOn() { stage = Stage::Attack; }
    void gateOff() { if (stage != Stage::Idle) stage = Stage::Release; }
    bool active() const { return stage != Stage::Idle; }
    float next() {
        switch (stage) {
            case Stage::Idle: value = 0.0f; break;
            case Stage::Attack: value += aRate; if (value >= 1.0f) { value = 1.0f; stage = Stage::Decay; } break;
            case Stage::Decay:
                value -= dRate;
                if (value <= sustain) { value = sustain; stage = (sustain <= 0.0f) ? Stage::Idle : Stage::Sustain; }
                break;
            case Stage::Sustain: value = sustain; break;
            case Stage::Release: value -= rRate; if (value <= 0.0f) { value = 0.0f; stage = Stage::Idle; } break;
        }
        return value;
    }
};

struct SVF {
    float ic1 = 0, ic2 = 0, g = 0, k = 0, a1 = 0, a2 = 0, a3 = 0, sr = 44100.0f;
    void setSampleRate(float s) { sr = s; }
    void set(float cutoffHz, float resonance) {
        cutoffHz = clampf(cutoffHz, 20.0f, sr * 0.45f);
        g = std::tan(static_cast<float>(kPi) * cutoffHz / sr);
        k = 2.0f - 1.98f * clampf(resonance, 0.0f, 1.0f);
        a1 = 1.0f / (1.0f + g * (g + k)); a2 = g * a1; a3 = g * a2;
    }
    float lp(float x) {
        float v3 = x - ic2, v1 = a1 * ic1 + a2 * v3, v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.0f * v1 - ic1; ic2 = 2.0f * v2 - ic2; return flushDenorm(v2);
    }
    float hp(float x) {
        float v3 = x - ic2, v1 = a1 * ic1 + a2 * v3, v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.0f * v1 - ic1; ic2 = 2.0f * v2 - ic2; return flushDenorm(x - k * v1 - v2);
    }
    float bp(float x) {
        float v3 = x - ic2, v1 = a1 * ic1 + a2 * v3, v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.0f * v1 - ic1; ic2 = 2.0f * v2 - ic2; return flushDenorm(v1);
    }
    void reset() { ic1 = ic2 = 0; }
};

// ---- Polyphonic synth voice ---------------------------------------------
struct SynthVoice {
    Oscillator osc, sub;
    ADSR amp, fenv;
    SVF filter;
    float sr = 44100.0f, velocity = 0.0f;
    int note = -1; bool busy = false; int gateCountdown = -1;
    float subLevel = 0.5f, baseCut = 380.0f, cutEnvAmt = 5200.0f;

    void init(float sampleRate) { sr = sampleRate; filter.setSampleRate(sampleRate); setPreset(0); }

    void setPreset(int p) {
        switch (p) {
            case AB_SYNTH_BASS:
                osc.wave = Wave::Saw; sub.wave = Wave::Square; subLevel = 0.7f;
                amp.configure(sr, 0.004f, 0.12f, 0.65f, 0.10f);
                fenv.configure(sr, 0.004f, 0.12f, 0.30f, 0.10f);
                baseCut = 230.0f; cutEnvAmt = 2600.0f; break;
            case AB_SYNTH_LEAD:
                osc.wave = Wave::Saw; sub.wave = Wave::Saw; subLevel = 0.4f;
                amp.configure(sr, 0.005f, 0.16f, 0.80f, 0.18f);
                fenv.configure(sr, 0.006f, 0.22f, 0.40f, 0.20f);
                baseCut = 720.0f; cutEnvAmt = 6200.0f; break;
            case AB_SYNTH_KEYS:
                osc.wave = Wave::Triangle; sub.wave = Wave::Sine; subLevel = 0.35f;
                amp.configure(sr, 0.003f, 0.20f, 0.55f, 0.22f);
                fenv.configure(sr, 0.004f, 0.16f, 0.35f, 0.16f);
                baseCut = 1300.0f; cutEnvAmt = 3000.0f; break;
            default: // Pluck
                osc.wave = Wave::Saw; sub.wave = Wave::Square; subLevel = 0.30f;
                amp.configure(sr, 0.003f, 0.11f, 0.0f, 0.12f);
                fenv.configure(sr, 0.002f, 0.10f, 0.20f, 0.12f);
                baseCut = 520.0f; cutEnvAmt = 5400.0f; break;
        }
    }
    void noteOn(int n, float vel, int gateSamples) {
        note = n; velocity = vel; busy = true; gateCountdown = gateSamples;
        double hz = midiToHz(n);
        osc.setFreq(hz, sr); sub.setFreq(hz * 0.5, sr);
        amp.gateOn(); fenv.gateOn();
    }
    float render() {
        if (!busy) return 0.0f;
        if (gateCountdown > 0 && --gateCountdown == 0) { amp.gateOff(); fenv.gateOff(); }
        float a = amp.next();
        if (!amp.active()) { busy = false; note = -1; return 0.0f; }
        float fe = fenv.next();
        float base = baseCut + 22.0f * static_cast<float>(note - 48);
        float cutoff = base + fe * cutEnvAmt * (0.4f + 0.6f * velocity);
        filter.set(cutoff, 0.62f);
        float raw = osc.next() + subLevel * sub.next();
        return filter.lp(raw * 0.5f) * a * velocity;
    }
};

// ---- Multi-type drum voice ----------------------------------------------
struct DrumVoice {
    int type = AB_DRUM_KICK;
    float sr = 44100.0f;
    ADSR amp; Oscillator osc; SVF filt; Noise noise;
    bool busy = false; float vel = 0.0f, pitchEnv = 0.0f;
    // params
    float pStart = 150, pEnd = 48, pDecay = 0.9988f;
    float toneLevel = 1.0f, noiseLevel = 0.0f, level = 1.0f;
    int filtMode = 0;          // 0 none, 1 lp, 2 hp, 3 bp
    bool pitchMod = true;

    void setType(int t, float s) {
        type = t; sr = s; filt.setSampleRate(s); filt.reset();
        osc.wave = Wave::Sine; pitchMod = true; level = 1.0f;
        switch (t) {
            case AB_DRUM_SNARE:
                amp.configure(s, 0.001f, 0.16f, 0.0f, 0.05f); osc.wave = Wave::Triangle;
                pStart = 220; pEnd = 180; pDecay = 0.992f; toneLevel = 0.5f; noiseLevel = 0.9f;
                filtMode = 3; filt.set(1900, 0.3f); break;
            case AB_DRUM_HAT:
                amp.configure(s, 0.0005f, 0.045f, 0.0f, 0.03f); toneLevel = 0; noiseLevel = 0.8f;
                filtMode = 2; filt.set(8200, 0.2f); level = 0.7f; break;
            case AB_DRUM_OPENHAT:
                amp.configure(s, 0.0008f, 0.24f, 0.0f, 0.06f); toneLevel = 0; noiseLevel = 0.7f;
                filtMode = 2; filt.set(7600, 0.2f); level = 0.6f; break;
            case AB_DRUM_CLAP:
                amp.configure(s, 0.001f, 0.13f, 0.0f, 0.05f); toneLevel = 0; noiseLevel = 1.0f;
                filtMode = 3; filt.set(1300, 0.35f); level = 0.9f; break;
            case AB_DRUM_TOM:
                amp.configure(s, 0.001f, 0.34f, 0.0f, 0.06f); osc.wave = Wave::Sine;
                pStart = 165; pEnd = 92; pDecay = 0.9992f; toneLevel = 1.0f; noiseLevel = 0; filtMode = 0; break;
            case AB_DRUM_RIM:
                amp.configure(s, 0.0005f, 0.04f, 0.0f, 0.02f); osc.wave = Wave::Square;
                pStart = 420; pEnd = 400; pDecay = 0.99f; toneLevel = 0.7f; noiseLevel = 0.3f;
                filtMode = 3; filt.set(2200, 0.3f); level = 0.9f; break;
            case AB_DRUM_PERC:
                amp.configure(s, 0.001f, 0.11f, 0.0f, 0.04f); osc.wave = Wave::Triangle;
                pStart = 440; pEnd = 300; pDecay = 0.995f; toneLevel = 0.8f; noiseLevel = 0.3f;
                filtMode = 3; filt.set(3000, 0.3f); level = 0.8f; break;
            default: // KICK
                amp.configure(s, 0.001f, 0.30f, 0.0f, 0.05f); osc.wave = Wave::Sine;
                pStart = 150; pEnd = 48; pDecay = 0.9988f; toneLevel = 1.1f; noiseLevel = 0; filtMode = 0; break;
        }
    }
    void trigger(float v) { vel = v; busy = true; amp.value = 0.0f; amp.gateOn(); pitchEnv = 1.0f; osc.phase = 0.0; }
    float render() {
        if (!busy) return 0.0f;
        float a = amp.next();
        if (!amp.active()) { busy = false; return 0.0f; }
        float out = 0.0f;
        if (toneLevel > 0) {
            double f = pitchMod ? (pEnd + (pStart - pEnd) * pitchEnv) : pStart;
            pitchEnv *= pDecay;
            osc.setFreq(f, sr);
            out += osc.next() * toneLevel;
        }
        if (noiseLevel > 0) {
            float n = noise.next();
            if (filtMode == 1) n = filt.lp(n);
            else if (filtMode == 2) n = filt.hp(n);
            else if (filtMode == 3) n = filt.bp(n);
            out += n * noiseLevel;
        }
        return out * a * vel * level;
    }
};

// ---- Master FX ----------------------------------------------------------
struct Delay {
    static constexpr int kMax = 96000;
    float bufL[kMax]; float bufR[kMax];
    int writeIdx = 0, samples = 12000;
    float feedback = 0.34f, mix = 0.20f;
    void init() { std::memset(bufL, 0, sizeof(bufL)); std::memset(bufR, 0, sizeof(bufR)); }
    void setTime(int s) { samples = s < 1 ? 1 : (s >= kMax ? kMax - 1 : s); }
    void process(float &l, float &r) {
        int readIdx = writeIdx - samples; if (readIdx < 0) readIdx += kMax;
        float dl = bufL[readIdx], dr = bufR[readIdx];
        bufL[writeIdx] = flushDenorm(l + dr * feedback);
        bufR[writeIdx] = flushDenorm(r + dl * feedback);
        if (++writeIdx >= kMax) writeIdx = 0;
        l += dl * mix; r += dr * mix;
    }
};
struct Comb { float *buf; int size; int idx = 0; float fb; float store = 0;
    void process(float in, float &out) {
        float y = buf[idx];
        store = flushDenorm(y * 0.8f + store * 0.2f);
        buf[idx] = in + store * fb; if (++idx >= size) idx = 0; out += y;
    } };
struct Allpass { float *buf; int size; int idx = 0;
    float process(float in) {
        float y = buf[idx]; float out = -in + y;
        buf[idx] = flushDenorm(in + y * 0.5f); if (++idx >= size) idx = 0; return out;
    } };
struct Reverb {
    float combBuf[8][1700]; float apBuf[4][600];
    Comb combsL[4], combsR[4]; Allpass apL[2], apR[2]; float mix = 0.16f;
    void init() {
        std::memset(combBuf, 0, sizeof(combBuf)); std::memset(apBuf, 0, sizeof(apBuf));
        const int cl[4] = {1116, 1188, 1277, 1356}, cr[4] = {1139, 1211, 1300, 1379};
        for (int i = 0; i < 4; ++i) { combsL[i] = {combBuf[i], cl[i], 0, 0.78f, 0}; combsR[i] = {combBuf[i + 4], cr[i], 0, 0.78f, 0}; }
        const int al[2] = {556, 441}, ar[2] = {579, 464};
        for (int i = 0; i < 2; ++i) { apL[i] = {apBuf[i], al[i], 0}; apR[i] = {apBuf[i + 2], ar[i], 0}; }
    }
    void process(float &l, float &r) {
        float in = (l + r) * 0.5f * 0.5f, outL = 0, outR = 0;
        for (int i = 0; i < 4; ++i) { combsL[i].process(in, outL); combsR[i].process(in, outR); }
        for (int i = 0; i < 2; ++i) { outL = apL[i].process(outL); outR = apR[i].process(outR); }
        l += outL * mix; r += outR * mix;
    }
};
inline float softClip(float x) {
    if (x > 1.5f) x = 1.5f; else if (x < -1.5f) x = -1.5f;
    return x - (x * x * x) * (1.0f / 6.75f);
}

struct StepData { int16_t note; float vel; };

// ---- A track (one layer): synth pool OR drum voice ----------------------
struct Track {
    std::atomic<bool> active{false};
    std::atomic<bool> muted{false};
    int kind = AB_KIND_SYNTH;
    int sound = 0;
    SynthVoice synth[4];
    DrumVoice drum;
    StepData steps[AB_NUM_STEPS];

    void init(float sr) {
        for (auto &v : synth) v.init(sr);
        drum.setType(AB_DRUM_KICK, sr);
        for (auto &s : steps) s = {60, 0.0f};
    }
    void configure(int k, int snd, float sr) {
        kind = k; sound = snd;
        if (k == AB_KIND_SYNTH) { for (auto &v : synth) v.setPreset(snd); }
        else drum.setType(snd, sr);
    }
    SynthVoice *alloc() { for (auto &v : synth) if (!v.busy) return &v; return &synth[0]; }
    float render() {
        if (kind == AB_KIND_SYNTH) { float o = 0; for (auto &v : synth) o += v.render(); return o * 0.5f; }
        return drum.render();
    }
};

} // namespace

struct ABAudioCore {
    double sr = 44100.0;
    Track tracks[AB_MAX_TRACKS];
    Delay delay; Reverb reverb;

    std::atomic<double> bpm{112.0};
    std::atomic<int> playing{0};
    std::atomic<int> uiStep{-1};
    std::atomic<double> uiPos{-1.0};
    double samplesPerStep = 0.0, stepAccum = 0.0;
    int curStep = 0; bool lastPlaying = false;

    void recomputeStepLen() {
        double b = bpm.load(std::memory_order_relaxed);
        samplesPerStep = (60.0 / b) * sr / 4.0;
    }
    void triggerStep(int step) {
        int gate = static_cast<int>(samplesPerStep * 0.9);
        for (auto &t : tracks) {
            if (!t.active.load(std::memory_order_relaxed)) continue;
            StepData &sd = t.steps[step];
            if (sd.vel <= 0.0f) continue;
            if (t.kind == AB_KIND_SYNTH) t.alloc()->noteOn(sd.note, sd.vel, gate);
            else t.drum.trigger(sd.vel);
        }
    }
};

extern "C" {

ABAudioCore *ab_core_create(double sampleRate) {
    auto *c = new (std::nothrow) ABAudioCore();
    if (!c) return nullptr;
    c->sr = sampleRate > 0 ? sampleRate : 44100.0;
    for (auto &t : c->tracks) { t.active.store(false); t.muted.store(false); t.init(static_cast<float>(c->sr)); }
    c->delay.init(); c->reverb.init();
    c->recomputeStepLen();
    return c;
}

void ab_core_destroy(ABAudioCore *core) { delete core; }

void ab_core_set_tempo(ABAudioCore *core, double bpm) {
    if (!core) return;
    if (bpm < 20.0) bpm = 20.0; else if (bpm > 300.0) bpm = 300.0;
    core->bpm.store(bpm, std::memory_order_relaxed);
    core->recomputeStepLen();
    core->delay.setTime(static_cast<int>((60.0 / bpm) * core->sr / 2.0));
}

void ab_core_set_playing(ABAudioCore *core, int playing) {
    if (core) core->playing.store(playing ? 1 : 0, std::memory_order_relaxed);
}
int ab_core_current_step(ABAudioCore *core) { return core ? core->uiStep.load(std::memory_order_relaxed) : -1; }
double ab_core_play_position(ABAudioCore *core) { return core ? core->uiPos.load(std::memory_order_relaxed) : -1.0; }

int ab_core_track_count(ABAudioCore *core) {
    if (!core) return 0;
    int n = 0;
    for (auto &t : core->tracks) if (t.active.load(std::memory_order_relaxed)) ++n;
    return n;
}

int ab_core_add_track(ABAudioCore *core, int kind, int sound) {
    if (!core) return -1;
    for (int i = 0; i < AB_MAX_TRACKS; ++i) {
        Track &t = core->tracks[i];
        if (t.active.load(std::memory_order_relaxed)) continue;
        for (auto &s : t.steps) s = {60, 0.0f};
        t.muted.store(false, std::memory_order_relaxed);
        t.configure(kind, sound, static_cast<float>(core->sr));
        t.active.store(true, std::memory_order_release);
        return i;
    }
    return -1;
}

void ab_core_remove_track(ABAudioCore *core, int track) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS) return;
    core->tracks[track].active.store(false, std::memory_order_release);
}

void ab_core_clear_track(ABAudioCore *core, int track) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS) return;
    for (auto &s : core->tracks[track].steps) s.vel = 0.0f;
}

void ab_core_clear_all(ABAudioCore *core) {
    if (!core) return;
    for (auto &t : core->tracks) for (auto &s : t.steps) s.vel = 0.0f;
}

void ab_core_set_track_sound(ABAudioCore *core, int track, int sound) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS) return;
    core->tracks[track].configure(core->tracks[track].kind, sound, static_cast<float>(core->sr));
}

void ab_core_set_track_mute(ABAudioCore *core, int track, int muted) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS) return;
    core->tracks[track].muted.store(muted ? true : false, std::memory_order_relaxed);
}

void ab_core_set_step(ABAudioCore *core, int track, int step, int midiNote, int velocity) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS || step < 0 || step >= AB_NUM_STEPS) return;
    if (velocity < 0) velocity = 0; else if (velocity > 127) velocity = 127;
    core->tracks[track].steps[step].note = static_cast<int16_t>(midiNote);
    core->tracks[track].steps[step].vel = velocity / 127.0f;
}

void ab_core_note_on(ABAudioCore *core, int track, int midiNote, float velocity) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS) return;
    Track &t = core->tracks[track];
    if (!t.active.load(std::memory_order_relaxed)) return;
    if (t.kind == AB_KIND_SYNTH) t.alloc()->noteOn(midiNote, clampf(velocity, 0, 1), static_cast<int>(core->sr * 0.4));
    else t.drum.trigger(clampf(velocity, 0, 1));
}

void ab_core_render(ABAudioCore *core, float *left, float *right, int frames) {
    if (!core || !left || !right) return;
    const bool isPlaying = core->playing.load(std::memory_order_relaxed) != 0;

    if (isPlaying && !core->lastPlaying) {
        core->curStep = 0; core->stepAccum = 0.0;
        core->triggerStep(0); core->uiStep.store(0, std::memory_order_relaxed);
    } else if (!isPlaying && core->lastPlaying) {
        core->uiStep.store(-1, std::memory_order_relaxed);
        core->uiPos.store(-1.0, std::memory_order_relaxed);
    }
    core->lastPlaying = isPlaying;

    for (int i = 0; i < frames; ++i) {
        if (isPlaying) {
            core->stepAccum += 1.0;
            if (core->stepAccum >= core->samplesPerStep) {
                core->stepAccum -= core->samplesPerStep;
                core->curStep = (core->curStep + 1) % AB_NUM_STEPS;
                core->triggerStep(core->curStep);
                core->uiStep.store(core->curStep, std::memory_order_relaxed);
            }
        }

        float mix = 0.0f;
        for (auto &t : core->tracks) {
            if (!t.active.load(std::memory_order_relaxed) || t.muted.load(std::memory_order_relaxed)) continue;
            mix += t.render();
        }

        float l = mix, r = mix;
        core->delay.process(l, r);
        core->reverb.process(l, r);
        left[i] = softClip(l * 0.5f);
        right[i] = softClip(r * 0.5f);
    }

    if (isPlaying && core->samplesPerStep > 0.0)
        core->uiPos.store(core->curStep + core->stepAccum / core->samplesPerStep, std::memory_order_relaxed);
}

const char *ab_core_version(void) { return "Absound DSP 0.3.0 (multi-track)"; }

} // extern "C"
