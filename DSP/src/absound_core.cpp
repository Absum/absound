/*
 * Absound DSP core implementation. See absound_core.h.
 *
 * Single translation unit by design (M1): synthesis, FX and the sequencer live
 * together so the whole signal path is easy to read and build. Later milestones
 * can split this into separate files as the engine grows.
 *
 * Real-time rules observed in ab_core_render() and everything it calls: no heap
 * allocation, no locks, no exceptions. Parameters set from the UI thread are
 * plain scalar writes or std::atomic, which is safe enough for byte/double-sized
 * fields on the platforms we target (a known M1 simplification).
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

// ---- Deterministic white noise (fast LCG) -------------------------------
struct Noise {
    uint32_t state = 0x1234567u;
    inline float next() {
        state = state * 1664525u + 1013904223u;
        return static_cast<float>(static_cast<int32_t>(state)) * (1.0f / 2147483648.0f);
    }
};

// ---- PolyBLEP oscillator -------------------------------------------------
enum class Wave { Saw, Square, Triangle, Sine };

struct Oscillator {
    double phase = 0.0;   // 0..1
    double inc = 0.0;     // cycles/sample
    double triState = 0.0;
    Wave wave = Wave::Saw;

    void setFreq(double hz, double sr) { inc = hz / sr; }

    static double polyBlep(double t, double dt) {
        if (t < dt) { t /= dt; return t + t - t * t - 1.0; }
        if (t > 1.0 - dt) { t = (t - 1.0) / dt; return t * t + t + t + 1.0; }
        return 0.0;
    }

    float next() {
        const double t = phase;
        const double dt = inc;
        double v = 0.0;
        switch (wave) {
            case Wave::Saw:
                v = 2.0 * t - 1.0;
                v -= polyBlep(t, dt);
                break;
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
                // leaky integrator of the band-limited square -> triangle
                triState = dt * sq + (1.0 - dt) * triState;
                v = triState * 4.0;
                break;
            }
            case Wave::Sine:
                v = std::sin(t * kTwoPi);
                break;
        }
        phase += inc;
        if (phase >= 1.0) phase -= 1.0;
        return static_cast<float>(v);
    }
};

// ---- ADSR envelope -------------------------------------------------------
struct ADSR {
    enum class Stage { Idle, Attack, Decay, Sustain, Release };
    Stage stage = Stage::Idle;
    float value = 0.0f;
    float sr = 44100.0f;
    float aRate = 0, dRate = 0, rRate = 0, sustain = 0.7f;

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
            case Stage::Attack:
                value += aRate;
                if (value >= 1.0f) { value = 1.0f; stage = Stage::Decay; }
                break;
            case Stage::Decay:
                value -= dRate;
                if (value <= sustain) {
                    value = sustain;
                    // sustain<=0 means a one-shot (AD) envelope: fall silent and free.
                    stage = (sustain <= 0.0f) ? Stage::Idle : Stage::Sustain;
                }
                break;
            case Stage::Sustain: value = sustain; break;
            case Stage::Release:
                value -= rRate;
                if (value <= 0.0f) { value = 0.0f; stage = Stage::Idle; }
                break;
        }
        return value;
    }
};

// ---- TPT state-variable filter (Zavalishin) ------------------------------
struct SVF {
    float ic1 = 0, ic2 = 0, g = 0, k = 0, a1 = 0, a2 = 0, a3 = 0;
    float sr = 44100.0f;

    void setSampleRate(float s) { sr = s; }
    void set(float cutoffHz, float resonance) {
        cutoffHz = clampf(cutoffHz, 20.0f, sr * 0.45f);
        g = std::tan(static_cast<float>(kPi) * cutoffHz / sr);
        k = 2.0f - 1.98f * clampf(resonance, 0.0f, 1.0f); // damping
        a1 = 1.0f / (1.0f + g * (g + k));
        a2 = g * a1;
        a3 = g * a2;
    }
    // Low-pass output.
    float lp(float x) {
        float v3 = x - ic2;
        float v1 = a1 * ic1 + a2 * v3;
        float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.0f * v1 - ic1;
        ic2 = 2.0f * v2 - ic2;
        return flushDenorm(v2);
    }
    float hp(float x) {
        float v3 = x - ic2;
        float v1 = a1 * ic1 + a2 * v3;
        float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.0f * v1 - ic1;
        ic2 = 2.0f * v2 - ic2;
        float hpOut = x - k * v1 - v2;
        return flushDenorm(hpOut);
    }
    float bp(float x) {
        float v3 = x - ic2;
        float v1 = a1 * ic1 + a2 * v3;
        float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.0f * v1 - ic1;
        ic2 = 2.0f * v2 - ic2;
        return flushDenorm(v1);
    }
    void reset() { ic1 = ic2 = 0; }
};

// ---- Polyphonic synth voice ----------------------------------------------
struct SynthVoice {
    Oscillator osc, sub;
    ADSR amp, fenv;
    SVF filter;
    float sr = 44100.0f;
    float velocity = 0.0f;
    int note = -1;
    bool busy = false;
    int gateCountdown = -1;   // samples until auto note-off (-1 = hold until noteOff)

    // Preset-driven timbre params.
    float subLevel = 0.5f;
    float baseCut = 380.0f;     // filter cutoff floor (Hz)
    float cutEnvAmt = 5200.0f;  // env -> cutoff depth (Hz)

    void init(float sampleRate) {
        sr = sampleRate;
        filter.setSampleRate(sampleRate);
        setPreset(0);
    }

    // 0=Pluck, 1=Bass, 2=Lead, 3=Keys.
    void setPreset(int p) {
        switch (p) {
            case 1: // Bass
                osc.wave = Wave::Saw; sub.wave = Wave::Square; subLevel = 0.7f;
                amp.configure(sr, 0.004f, 0.12f, 0.65f, 0.10f);
                fenv.configure(sr, 0.004f, 0.12f, 0.30f, 0.10f);
                baseCut = 230.0f; cutEnvAmt = 2600.0f; break;
            case 2: // Lead
                osc.wave = Wave::Saw; sub.wave = Wave::Saw; subLevel = 0.4f;
                amp.configure(sr, 0.005f, 0.16f, 0.80f, 0.18f);
                fenv.configure(sr, 0.006f, 0.22f, 0.40f, 0.20f);
                baseCut = 720.0f; cutEnvAmt = 6200.0f; break;
            case 3: // Keys
                osc.wave = Wave::Triangle; sub.wave = Wave::Sine; subLevel = 0.35f;
                amp.configure(sr, 0.003f, 0.20f, 0.55f, 0.22f);
                fenv.configure(sr, 0.004f, 0.16f, 0.35f, 0.16f);
                baseCut = 1300.0f; cutEnvAmt = 3000.0f; break;
            default: // 0 Pluck
                osc.wave = Wave::Saw; sub.wave = Wave::Square; subLevel = 0.30f;
                amp.configure(sr, 0.003f, 0.11f, 0.0f, 0.12f);
                fenv.configure(sr, 0.002f, 0.10f, 0.20f, 0.12f);
                baseCut = 520.0f; cutEnvAmt = 5400.0f; break;
        }
    }
    // gateSamples > 0 schedules an automatic note-off after that many samples.
    void noteOn(int n, float vel, int gateSamples) {
        note = n; velocity = vel; busy = true; gateCountdown = gateSamples;
        double hz = midiToHz(n);
        osc.setFreq(hz, sr);
        sub.setFreq(hz * 0.5, sr);
        amp.gateOn();
        fenv.gateOn();
    }
    void noteOff() { amp.gateOff(); fenv.gateOff(); gateCountdown = -1; }

    float render() {
        if (!busy) return 0.0f;
        if (gateCountdown > 0 && --gateCountdown == 0) { amp.gateOff(); fenv.gateOff(); }
        float a = amp.next();
        if (!amp.active()) { busy = false; note = -1; return 0.0f; }
        float fe = fenv.next();
        // Filter sweeps from the preset's cutoff floor upward with the env; key-track a little.
        float base = baseCut + 22.0f * static_cast<float>(note - 48);
        float cutoff = base + fe * cutEnvAmt * (0.4f + 0.6f * velocity);
        filter.set(cutoff, 0.62f);
        float raw = osc.next() + subLevel * sub.next();
        float filtered = filter.lp(raw * 0.5f);
        return filtered * a * velocity;
    }
};

// ---- Drum voices ---------------------------------------------------------
struct Kick {
    ADSR amp; Oscillator osc; float sr = 44100.0f;
    float pitchEnv = 0.0f; bool busy = false; float vel = 0;
    void init(float s) { sr = s; osc.wave = Wave::Sine; amp.configure(s, 0.001f, 0.28f, 0.0f, 0.05f); }
    void trigger(float v) { vel = v; busy = true; pitchEnv = 1.0f; amp.value = 0.0f; amp.gateOn(); }
    float render() {
        if (!busy) return 0.0f;
        float a = amp.next();
        if (!amp.active()) { busy = false; return 0.0f; }
        pitchEnv *= 0.9988f; // ~150Hz -> ~48Hz drop
        osc.setFreq(48.0 + 150.0 * pitchEnv, sr);
        float body = static_cast<float>(std::sin(osc.phase * kTwoPi));
        float click = (a > 0.6f) ? (osc.phase < 0.5 ? 0.15f : -0.15f) * (a - 0.6f) : 0.0f;
        osc.phase += osc.inc;
        if (osc.phase >= 1.0) osc.phase -= 1.0;
        return (body + click) * a * vel * 1.1f;
    }
};

struct Snare {
    ADSR amp; SVF body; SVF bpNoise; Noise noise; float sr = 44100.0f;
    bool busy = false; float vel = 0; Oscillator tone;
    void init(float s) {
        sr = s; amp.configure(s, 0.001f, 0.14f, 0.0f, 0.04f);
        body.setSampleRate(s); bpNoise.setSampleRate(s);
        bpNoise.set(1900.0f, 0.3f); tone.wave = Wave::Triangle; tone.setFreq(185.0, s);
    }
    void trigger(float v) { vel = v; busy = true; amp.value = 0.0f; amp.gateOn(); }
    float render() {
        if (!busy) return 0.0f;
        float a = amp.next();
        if (!amp.active()) { busy = false; return 0.0f; }
        float n = bpNoise.bp(noise.next());
        float t = tone.next() * 0.5f;
        return (n * 0.9f + t * 0.5f) * a * vel;
    }
};

struct Hat {
    ADSR amp; SVF hp; Noise noise; float sr = 44100.0f; bool busy = false; float vel = 0;
    void init(float s) { sr = s; amp.configure(s, 0.0005f, 0.045f, 0.0f, 0.03f); hp.setSampleRate(s); hp.set(8200.0f, 0.2f); }
    void trigger(float v) { vel = v; busy = true; amp.value = 0.0f; amp.gateOn(); }
    float render() {
        if (!busy) return 0.0f;
        float a = amp.next();
        if (!amp.active()) { busy = false; return 0.0f; }
        return hp.hp(noise.next()) * a * vel * 0.7f;
    }
};

// ---- Stereo tempo-synced delay ------------------------------------------
struct Delay {
    static constexpr int kMax = 96000; // ~2s at 48k
    float bufL[kMax]; float bufR[kMax];
    int writeIdx = 0; int samples = 12000;
    float feedback = 0.34f; float mix = 0.20f;
    void init() { std::memset(bufL, 0, sizeof(bufL)); std::memset(bufR, 0, sizeof(bufR)); }
    void setTime(int s) { samples = s < 1 ? 1 : (s >= kMax ? kMax - 1 : s); }
    void process(float &l, float &r) {
        int readIdx = writeIdx - samples; if (readIdx < 0) readIdx += kMax;
        float dl = bufL[readIdx], dr = bufR[readIdx];
        bufL[writeIdx] = flushDenorm(l + dr * feedback); // ping-pong cross-feed
        bufR[writeIdx] = flushDenorm(r + dl * feedback);
        if (++writeIdx >= kMax) writeIdx = 0;
        l += dl * mix; r += dr * mix;
    }
};

// ---- Schroeder reverb (4 combs + 2 allpass per channel) ------------------
struct Comb {
    float *buf; int size; int idx = 0; float fb; float store = 0;
    void process(float in, float &out) {
        float y = buf[idx];
        store = flushDenorm(y * (1.0f - 0.2f) + store * 0.2f); // light damping
        buf[idx] = in + store * fb;
        if (++idx >= size) idx = 0;
        out += y;
    }
};
struct Allpass {
    float *buf; int size; int idx = 0;
    float process(float in) {
        float y = buf[idx];
        float out = -in + y;
        buf[idx] = flushDenorm(in + y * 0.5f);
        if (++idx >= size) idx = 0;
        return out;
    }
};

struct Reverb {
    // Buffer storage sized for the classic Freeverb tunings (at 44.1k).
    float combBuf[8][1700];
    float apBuf[4][600];
    Comb combsL[4], combsR[4];
    Allpass apL[2], apR[2];
    float mix = 0.16f;
    void init() {
        std::memset(combBuf, 0, sizeof(combBuf));
        std::memset(apBuf, 0, sizeof(apBuf));
        const int cl[4] = {1116, 1188, 1277, 1356};
        const int cr[4] = {1139, 1211, 1300, 1379};
        for (int i = 0; i < 4; ++i) {
            combsL[i] = {combBuf[i], cl[i], 0, 0.78f, 0};
            combsR[i] = {combBuf[i + 4], cr[i], 0, 0.78f, 0};
        }
        const int al[2] = {556, 441};
        const int ar[2] = {579, 464};
        for (int i = 0; i < 2; ++i) {
            apL[i] = {apBuf[i], al[i], 0};
            apR[i] = {apBuf[i + 2], ar[i], 0};
        }
    }
    void process(float &l, float &r) {
        float in = (l + r) * 0.5f * 0.5f;
        float outL = 0, outR = 0;
        for (int i = 0; i < 4; ++i) { combsL[i].process(in, outL); combsR[i].process(in, outR); }
        for (int i = 0; i < 2; ++i) { outL = apL[i].process(outL); outR = apR[i].process(outR); }
        l += outL * mix; r += outR * mix;
    }
};

inline float softClip(float x) {
    // Cubic soft clip then hard safety clamp.
    if (x > 1.5f) x = 1.5f; else if (x < -1.5f) x = -1.5f;
    return x - (x * x * x) * (1.0f / 6.75f);
}

} // namespace

// ---- The engine ----------------------------------------------------------
struct ABAudioCore {
    double sr = 44100.0;

    SynthVoice voices[6];
    Kick kick; Snare snare; Hat hat;
    Delay delay; Reverb reverb;

    // Pattern: per track, per step (note, velocity 0..1).
    struct StepData { int16_t note; float vel; };
    StepData steps[AB_NUM_TRACKS][AB_NUM_STEPS];

    // Transport (audio-thread state; scalars written from UI thread).
    std::atomic<double> bpm{112.0};
    std::atomic<int> playing{0};
    std::atomic<int> uiStep{-1};
    double samplesPerStep = 0.0;
    double stepAccum = 0.0;
    int curStep = 0;
    bool lastPlaying = false;

    void recomputeStepLen() {
        double b = bpm.load(std::memory_order_relaxed);
        // 16 steps == 4 beats (16th notes).
        samplesPerStep = (60.0 / b) * sr / 4.0;
    }

    int synthPreset = 0;

    void applyPreset(int p) {
        synthPreset = p;
        for (auto &v : voices) v.setPreset(p);
    }

    SynthVoice *allocVoice() {
        for (auto &v : voices) if (!v.busy) return &v;
        // steal the first (simple, fine for M1)
        return &voices[0];
    }

    void triggerStep(int step) {
        for (int t = 0; t < AB_NUM_TRACKS; ++t) {
            StepData &sd = steps[t][step];
            if (sd.vel <= 0.0f) continue;
            switch (t) {
                case AB_TRACK_SYNTH: {
                    SynthVoice *v = allocVoice();
                    // Release before the next step so notes are plucky, never stuck.
                    int gate = static_cast<int>(samplesPerStep * 0.9);
                    v->noteOn(sd.note, sd.vel, gate);
                    break;
                }
                case AB_TRACK_KICK: kick.trigger(sd.vel); break;
                case AB_TRACK_SNARE: snare.trigger(sd.vel); break;
                case AB_TRACK_HAT: hat.trigger(sd.vel); break;
            }
        }
    }
};

extern "C" {

ABAudioCore *ab_core_create(double sampleRate) {
    auto *c = new (std::nothrow) ABAudioCore();
    if (!c) return nullptr;
    c->sr = sampleRate > 0 ? sampleRate : 44100.0;
    for (auto &v : c->voices) v.init(static_cast<float>(c->sr));
    c->kick.init(static_cast<float>(c->sr));
    c->snare.init(static_cast<float>(c->sr));
    c->hat.init(static_cast<float>(c->sr));
    c->delay.init();
    c->reverb.init();
    for (int t = 0; t < AB_NUM_TRACKS; ++t)
        for (int s = 0; s < AB_NUM_STEPS; ++s) c->steps[t][s] = {60, 0.0f};
    c->recomputeStepLen();
    return c;
}

void ab_core_destroy(ABAudioCore *core) { delete core; }

void ab_core_set_tempo(ABAudioCore *core, double bpm) {
    if (!core) return;
    if (bpm < 20.0) bpm = 20.0; else if (bpm > 300.0) bpm = 300.0;
    core->bpm.store(bpm, std::memory_order_relaxed);
    core->recomputeStepLen();
    // sync delay to a 1/8 note
    core->delay.setTime(static_cast<int>((60.0 / bpm) * core->sr / 2.0));
}

void ab_core_set_playing(ABAudioCore *core, int playing) {
    if (!core) return;
    core->playing.store(playing ? 1 : 0, std::memory_order_relaxed);
}

int ab_core_current_step(ABAudioCore *core) {
    return core ? core->uiStep.load(std::memory_order_relaxed) : -1;
}

void ab_core_set_step(ABAudioCore *core, int track, int step, int midiNote, int velocity) {
    if (!core || track < 0 || track >= AB_NUM_TRACKS || step < 0 || step >= AB_NUM_STEPS) return;
    if (velocity < 0) velocity = 0; else if (velocity > 127) velocity = 127;
    core->steps[track][step].note = static_cast<int16_t>(midiNote);
    core->steps[track][step].vel = velocity / 127.0f;
}

void ab_core_clear(ABAudioCore *core) {
    if (!core) return;
    for (int t = 0; t < AB_NUM_TRACKS; ++t)
        for (int s = 0; s < AB_NUM_STEPS; ++s) core->steps[t][s] = {60, 0.0f};
}

void ab_core_set_synth_preset(ABAudioCore *core, int preset) {
    if (!core) return;
    if (preset < 0) preset = 0; else if (preset > 3) preset = 3;
    core->applyPreset(preset);
}

void ab_core_note_on(ABAudioCore *core, int track, int midiNote, float velocity) {
    if (!core) return;
    switch (track) {
        case AB_TRACK_SYNTH:
            // Live trigger holds for ~0.4s then auto-releases (until real note-off plumbing in M3).
            core->allocVoice()->noteOn(midiNote, clampf(velocity, 0, 1), static_cast<int>(core->sr * 0.4));
            break;
        case AB_TRACK_KICK: core->kick.trigger(clampf(velocity, 0, 1)); break;
        case AB_TRACK_SNARE: core->snare.trigger(clampf(velocity, 0, 1)); break;
        case AB_TRACK_HAT: core->hat.trigger(clampf(velocity, 0, 1)); break;
    }
}

void ab_core_render(ABAudioCore *core, float *left, float *right, int frames) {
    if (!core || !left || !right) return;
    const bool isPlaying = core->playing.load(std::memory_order_relaxed) != 0;

    // Handle start/stop edges.
    if (isPlaying && !core->lastPlaying) {
        core->curStep = 0;
        core->stepAccum = 0.0;
        core->triggerStep(0);
        core->uiStep.store(0, std::memory_order_relaxed);
    } else if (!isPlaying && core->lastPlaying) {
        core->uiStep.store(-1, std::memory_order_relaxed);
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

        // Sum voices.
        float dry = 0.0f;
        for (auto &v : core->voices) dry += v.render();
        dry *= 0.5f; // synth headroom
        float drums = core->kick.render() + core->snare.render() + core->hat.render();

        float l = dry + drums;
        float r = dry + drums;

        // FX chain: delay (synth+drums) then reverb, then limiter.
        core->delay.process(l, r);
        core->reverb.process(l, r);
        left[i] = softClip(l * 0.62f);
        right[i] = softClip(r * 0.62f);
    }
}

const char *ab_core_version(void) { return "Absound DSP 0.2.0 (M1 engine)"; }

} // extern "C"
