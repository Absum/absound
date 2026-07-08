/*
 * Absound DSP core implementation — engine v2. See absound_core.h.
 *
 * Stereo, patch-driven synthesis. Each synth track renders through a full
 * subtractive voice (unison osc1 + osc2 + sub + noise -> drive -> SVF ->
 * velocity-sensitive envelopes, with LFO and glide) into a per-track channel
 * strip (smoothed gain/pan + delay/reverb sends), summed on stereo buses,
 * FX processed, then soft-clipped with proper headroom.
 *
 * Real-time rules in ab_core_render(): no heap allocation, no locks, no
 * exceptions. UI-thread parameter changes arrive either as atomics or via the
 * staged-patch mailbox (patchDirty flag) consumed at control-block boundaries.
 * Filter coefficients and channel smoothing update at control rate
 * (kCtrlBlock samples), not per sample.
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
constexpr int kCtrlBlock = 32;          // control-rate period in samples
constexpr int kVoicesPerTrack = 5;

inline double midiToHz(double note) { return 440.0 * std::pow(2.0, (note - 69.0) / 12.0); }
inline float clampf(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }
inline int clampi(int x, int lo, int hi) { return x < lo ? lo : (x > hi ? hi : x); }
inline float flushDenorm(float x) { return std::fabs(x) < 1.0e-20f ? 0.0f : x; }
inline float sanitize(float x) { return std::isfinite(x) ? x : 0.0f; }

// ---- Deterministic white noise (fast LCG) --------------------------------
struct Noise {
    uint32_t state = 0x1234567u;
    inline float next() {
        state = state * 1664525u + 1013904223u;
        return static_cast<float>(static_cast<int32_t>(state)) * (1.0f / 2147483648.0f);
    }
};

// ---- PolyBLEP oscillator (one phase; a voice owns several) ----------------
struct BlepOsc {
    double phase = 0.0, inc = 0.0, triState = 0.0;
    int wave = AB_WAVE_SAW;

    static double polyBlep(double t, double dt) {
        if (t < dt) { t /= dt; return t + t - t * t - 1.0; }
        if (t > 1.0 - dt) { t = (t - 1.0) / dt; return t * t + t + t + 1.0; }
        return 0.0;
    }
    inline float next() {
        const double t = phase, dt = inc;
        double v = 0.0;
        switch (wave) {
            case AB_WAVE_SAW: v = 2.0 * t - 1.0; v -= polyBlep(t, dt); break;
            case AB_WAVE_SQUARE: {
                v = t < 0.5 ? 1.0 : -1.0;
                v += polyBlep(t, dt);
                double t2 = t + 0.5; if (t2 >= 1.0) t2 -= 1.0;
                v -= polyBlep(t2, dt);
                break;
            }
            case AB_WAVE_TRI: {
                double sq = t < 0.5 ? 1.0 : -1.0;
                sq += polyBlep(t, dt);
                double t2 = t + 0.5; if (t2 >= 1.0) t2 -= 1.0;
                sq -= polyBlep(t2, dt);
                triState = dt * sq + (1.0 - dt) * triState;
                v = triState * 4.0;
                break;
            }
            default: v = std::sin(t * kTwoPi); break;
        }
        phase += inc; if (phase >= 1.0) phase -= 1.0;
        return static_cast<float>(v);
    }
};

// ---- ADSR with squared (exponential-feel) output --------------------------
struct ADSR {
    enum class Stage { Idle, Attack, Decay, Sustain, Release };
    Stage stage = Stage::Idle;
    float value = 0.0f, sr = 44100.0f, aRate = 0, dRate = 0, rRate = 0, sustain = 0.7f;

    void configure(float sampleRate, float a, float d, float s, float r) {
        sr = sampleRate;
        aRate = 1.0f / (std::fmax(a, 1.0e-4f) * sr);
        dRate = 1.0f / (std::fmax(d, 1.0e-4f) * sr);
        rRate = 1.0f / (std::fmax(r, 1.0e-4f) * sr);
        sustain = clampf(s, 0.0f, 1.0f);
    }
    void gateOn() { stage = Stage::Attack; }
    void gateOff() { if (stage != Stage::Idle) stage = Stage::Release; }
    void hardReset() { stage = Stage::Idle; value = 0.0f; }
    bool active() const { return stage != Stage::Idle; }

    inline float next() {
        switch (stage) {
            case Stage::Idle: value = 0.0f; break;
            case Stage::Attack:
                value += aRate;
                if (value >= 1.0f) { value = 1.0f; stage = Stage::Decay; }
                break;
            case Stage::Decay:
                value -= dRate;
                if (value <= sustain) { value = sustain; stage = (sustain <= 0.0f) ? Stage::Idle : Stage::Sustain; }
                break;
            case Stage::Sustain: value = sustain; break;
            case Stage::Release:
                value -= rRate;
                if (value <= 0.0f) { value = 0.0f; stage = Stage::Idle; }
                break;
        }
        return value * value;   // squared -> exponential-ish curve
    }
};

// ---- TPT state-variable filter --------------------------------------------
struct SVF {
    float ic1 = 0, ic2 = 0, g = 0, k = 0, a1 = 0, a2 = 0, a3 = 0, sr = 44100.0f;
    void setSampleRate(float s) { sr = s; }
    void set(float cutoffHz, float resonance) {
        cutoffHz = clampf(cutoffHz, 20.0f, sr * 0.45f);
        g = std::tan(static_cast<float>(kPi) * cutoffHz / sr);
        k = 2.0f - 1.9f * clampf(resonance, 0.0f, 1.0f);
        a1 = 1.0f / (1.0f + g * (g + k)); a2 = g * a1; a3 = g * a2;
    }
    // Runs all three outputs; caller picks by type.
    inline float process(float x, int type) {
        float v3 = x - ic2, v1 = a1 * ic1 + a2 * v3, v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = flushDenorm(2.0f * v1 - ic1); ic2 = flushDenorm(2.0f * v2 - ic2);
        switch (type) {
            case AB_FILTER_BP: return v1;
            case AB_FILTER_HP: return x - k * v1 - v2;
            default: return v2;                        // LP
        }
    }
    void reset() { ic1 = ic2 = 0; }
};

// ---- One-pole smoother (control-rate) --------------------------------------
struct Smooth {
    float v = 0, target = 0;
    void snap(float x) { v = target = x; }
    inline float tick(float coef) { v += coef * (target - v); return v; }
};

// ---- LFO -------------------------------------------------------------------
struct LFO {
    double phase = 0.0;
    float held = 0.0f;   // for S&H
    Noise rng;
    // Returns -1..1; advances by one control block.
    float tick(int shape, double rateHz, double sr) {
        double inc = rateHz * kCtrlBlock / sr;
        phase += inc;
        if (phase >= 1.0) { phase -= std::floor(phase); held = rng.next(); }
        switch (shape) {
            case 1: return static_cast<float>(4.0 * std::fabs(phase - 0.5) - 1.0); // tri
            case 2: return held;                                                    // S&H
            default: return static_cast<float>(std::sin(phase * kTwoPi));           // sine
        }
    }
};

// ---- Derived (audio-thread) patch state ------------------------------------
struct VoiceConfig {
    ABPatch p;                    // live copy
    // Precomputed per patch apply:
    int unison = 1;
    double detuneRatio[AB_MAX_UNISON];   // frequency multipliers
    float panL[AB_MAX_UNISON], panR[AB_MAX_UNISON]; // equal-power per unison voice
    float unisonNorm = 1.0f;
    double osc2Ratio = 1.0;

    void recompute() {
        unison = clampi(p.unison, 1, AB_MAX_UNISON);
        float width = clampf(p.unisonWidth, 0.0f, 1.0f);
        for (int i = 0; i < unison; ++i) {
            float offset = (unison == 1) ? 0.0f
                : (static_cast<float>(i) / (unison - 1)) * 2.0f - 1.0f;   // -1..1
            detuneRatio[i] = std::pow(2.0, offset * clampf(p.unisonDetune, 0.0f, 50.0f) / 1200.0);
            float pan = offset * width;                                    // -1..1
            float a = (pan + 1.0f) * 0.25f * static_cast<float>(kPi);      // equal power
            panL[i] = std::cos(a); panR[i] = std::sin(a);
        }
        unisonNorm = 1.0f / std::sqrt(static_cast<float>(unison));
        osc2Ratio = std::pow(2.0, (clampi(p.osc2Semi, -24, 24) + clampf(p.osc2Fine, -50.0f, 50.0f) / 100.0) / 12.0);
    }
};

// ---- Synth voice (stereo) ---------------------------------------------------
struct SynthVoice {
    BlepOsc osc1[AB_MAX_UNISON];
    BlepOsc osc2, sub;
    ADSR amp, mod;
    SVF filter;
    Noise noise;
    LFO lfo;
    float sr = 44100.0f;
    float velocity = 1.0f;
    int note = -1;
    bool busy = false;
    int gateCountdown = -1;
    double curNote = 60.0, targetNote = 60.0; // glide in note space
    double glideCoef = 1.0;                    // per-sample approach
    // control-block cached values
    float cbLfo = 0.0f;
    int cbCount = 0;

    void init(float sampleRate) {
        sr = sampleRate;
        filter.setSampleRate(sampleRate);
    }
    void hardReset() {
        busy = false; note = -1; gateCountdown = -1;
        amp.hardReset(); mod.hardReset(); filter.reset();
    }
    void applyEnvelopes(const ABPatch &p) {
        amp.configure(sr, p.ampA, p.ampD, p.ampS, p.ampR);
        mod.configure(sr, p.modA, p.modD, p.modS, p.modR);
    }
    void noteOn(const VoiceConfig &cfg, int n, float vel, int gateSamples, double glideFromNote) {
        const ABPatch &p = cfg.p;
        note = n; velocity = clampf(vel, 0.0f, 1.0f); busy = true; gateCountdown = gateSamples;
        targetNote = n;
        if (p.glide > 0.001f && glideFromNote > 0.0) {
            curNote = glideFromNote;
            glideCoef = 1.0 - std::exp(-1.0 / (p.glide * sr * 0.25));
        } else {
            curNote = n;
            glideCoef = 1.0;
        }
        for (int i = 0; i < AB_MAX_UNISON; ++i) osc1[i].wave = p.osc1Wave;
        osc2.wave = p.osc2Wave;
        sub.wave = AB_WAVE_SINE;
        applyEnvelopes(p);
        amp.gateOn(); mod.gateOn();
        cbCount = 0;
    }

    // Update frequencies from curNote (called at control rate + on glide).
    inline void updateFreqs(const VoiceConfig &cfg, double pitchMod) {
        double hz = midiToHz(curNote + pitchMod);
        for (int i = 0; i < cfg.unison; ++i) osc1[i].inc = hz * cfg.detuneRatio[i] / sr;
        osc2.inc = hz * cfg.osc2Ratio / sr;
        sub.inc = hz * 0.5 / sr;
    }

    // Render one sample into l/r. Control-rate work happens every kCtrlBlock calls.
    inline void render(const VoiceConfig &cfg, double bpm, float &outL, float &outR) {
        if (!busy) return;
        const ABPatch &p = cfg.p;

        if (gateCountdown > 0 && --gateCountdown == 0) { amp.gateOff(); mod.gateOff(); }

        float a = amp.next();
        if (!amp.active()) { busy = false; note = -1; return; }
        float m = mod.next();

        if (cbCount-- <= 0) {
            cbCount = kCtrlBlock - 1;
            // LFO rate (free or tempo-synced)
            double rate = p.lfoRateHz;
            if (p.lfoSync > 0) rate = (bpm / 60.0) * (p.lfoSync / 4.0);
            cbLfo = lfo.tick(p.lfoShape, rate, sr) * clampf(p.lfoDepth, 0.0f, 1.0f);

            // glide
            curNote += (targetNote - curNote) * glideCoef * kCtrlBlock;
            if (std::fabs(targetNote - curNote) < 0.001) curNote = targetNote;

            double pitchMod = (p.lfoTarget == AB_LFO_PITCH) ? cbLfo * 0.5 : 0.0; // ±half-semitone vibrato
            updateFreqs(cfg, pitchMod);

            // filter coefficients at control rate
            float cutoff = p.cutoff
                + p.keyTrack * 32.0f * (static_cast<float>(note) - 60.0f)
                + p.envAmount * 8000.0f * m * (0.4f + 0.6f * velocity * p.velAmount + (1.0f - p.velAmount) * 0.6f);
            if (p.lfoTarget == AB_LFO_CUTOFF) cutoff *= std::pow(2.0f, cbLfo * 2.0f);
            filter.set(cutoff, p.resonance);
        }

        // --- oscillator sum (osc1 unison is the stereo part) ---
        float monoPart = 0.0f;
        float uniL = 0.0f, uniR = 0.0f;
        float osc1Gain = (1.0f - clampf(p.oscMix, 0.0f, 1.0f)) * cfg.unisonNorm;
        for (int i = 0; i < cfg.unison; ++i) {
            float s = osc1[i].next() * osc1Gain;
            uniL += s * cfg.panL[i];
            uniR += s * cfg.panR[i];
        }
        monoPart += osc2.next() * clampf(p.oscMix, 0.0f, 1.0f);
        monoPart += sub.next() * clampf(p.subLevel, 0.0f, 1.0f);
        monoPart += noise.next() * clampf(p.noiseLevel, 0.0f, 1.0f) * 0.7f;

        // Drive -> filter (mid channel; unison spread stays stereo through a
        // shared filter approximation: filter the mid, add back the side).
        float mid = (uniL + uniR) * 0.5f + monoPart;
        float sideL = uniL - (uniL + uniR) * 0.5f;
        float sideR = uniR - (uniL + uniR) * 0.5f;
        float driven = mid;
        if (p.drive > 0.001f) {
            float d = 1.0f + p.drive * 5.0f;
            driven = std::tanh(mid * d) / std::tanh(d) * 0.9f;
        }
        float filtered = filter.process(driven * 0.75f, p.filterType);

        float ampMod = 1.0f;
        if (p.lfoTarget == AB_LFO_AMP) ampMod = 1.0f - clampf(0.5f + 0.5f * cbLfo, 0.0f, 1.0f) * clampf(p.lfoDepth, 0.0f, 1.0f);
        float vel = (1.0f - p.velAmount) + p.velAmount * velocity;
        float g = a * vel * ampMod;

        float panLfo = (p.lfoTarget == AB_LFO_PAN) ? cbLfo : 0.0f;
        float pl = clampf(1.0f - panLfo, 0.0f, 1.0f), pr = clampf(1.0f + panLfo, 0.0f, 1.0f);

        outL += (filtered + sideL * 0.8f) * g * pl;
        outR += (filtered + sideR * 0.8f) * g * pr;
    }
};

// ---- Drum voice (with declick ramp) ----------------------------------------
struct DrumVoice {
    int type = AB_DRUM_KICK;
    float sr = 44100.0f;
    ADSR amp; BlepOsc osc; SVF filt; Noise noise;
    bool busy = false; float vel = 0.0f, pitchEnv = 0.0f;
    float pStart = 150, pEnd = 48, pDecay = 0.9988f;
    float toneLevel = 1.0f, noiseLevel = 0.0f, level = 1.0f;
    int filtMode = AB_FILTER_LP; bool useFilt = false;
    // declick: fade out current tail before retriggering
    int declick = 0; float pendingVel = -1.0f;
    static constexpr int kDeclick = 64;

    void setType(int t, float s) {
        type = t; sr = s; filt.setSampleRate(s); filt.reset();
        osc.wave = AB_WAVE_SINE; level = 1.0f; useFilt = false;
        switch (t) {
            case AB_DRUM_SNARE:
                amp.configure(s, 0.001f, 0.16f, 0.0f, 0.05f); osc.wave = AB_WAVE_TRI;
                pStart = 220; pEnd = 180; pDecay = 0.992f; toneLevel = 0.5f; noiseLevel = 0.9f;
                useFilt = true; filtMode = AB_FILTER_BP; filt.set(1900, 0.3f); break;
            case AB_DRUM_HAT:
                amp.configure(s, 0.0005f, 0.045f, 0.0f, 0.03f); toneLevel = 0; noiseLevel = 0.8f;
                useFilt = true; filtMode = AB_FILTER_HP; filt.set(8200, 0.2f); level = 0.7f; break;
            case AB_DRUM_OPENHAT:
                amp.configure(s, 0.0008f, 0.24f, 0.0f, 0.06f); toneLevel = 0; noiseLevel = 0.7f;
                useFilt = true; filtMode = AB_FILTER_HP; filt.set(7600, 0.2f); level = 0.6f; break;
            case AB_DRUM_CLAP:
                amp.configure(s, 0.001f, 0.13f, 0.0f, 0.05f); toneLevel = 0; noiseLevel = 1.0f;
                useFilt = true; filtMode = AB_FILTER_BP; filt.set(1300, 0.35f); level = 0.9f; break;
            case AB_DRUM_TOM:
                amp.configure(s, 0.001f, 0.34f, 0.0f, 0.06f);
                pStart = 165; pEnd = 92; pDecay = 0.9992f; toneLevel = 1.0f; noiseLevel = 0; break;
            case AB_DRUM_RIM:
                amp.configure(s, 0.0005f, 0.04f, 0.0f, 0.02f); osc.wave = AB_WAVE_SQUARE;
                pStart = 420; pEnd = 400; pDecay = 0.99f; toneLevel = 0.7f; noiseLevel = 0.3f;
                useFilt = true; filtMode = AB_FILTER_BP; filt.set(2200, 0.3f); level = 0.9f; break;
            case AB_DRUM_PERC:
                amp.configure(s, 0.001f, 0.11f, 0.0f, 0.04f); osc.wave = AB_WAVE_TRI;
                pStart = 440; pEnd = 300; pDecay = 0.995f; toneLevel = 0.8f; noiseLevel = 0.3f;
                useFilt = true; filtMode = AB_FILTER_BP; filt.set(3000, 0.3f); break;
            default: /* kick */
                amp.configure(s, 0.001f, 0.30f, 0.0f, 0.05f);
                pStart = 150; pEnd = 48; pDecay = 0.9988f; toneLevel = 1.1f; noiseLevel = 0; break;
        }
    }
    void trigger(float v) {
        if (busy && declick == 0) { declick = kDeclick; pendingVel = v; return; }
        if (busy && declick > 0) { pendingVel = v; return; }   // already fading; queue
        start(v);
    }
    void start(float v) {
        vel = v; busy = true; declick = 0; pendingVel = -1.0f;
        amp.hardReset(); amp.gateOn(); pitchEnv = 1.0f; osc.phase = 0.0;
    }
    void hardReset() { busy = false; declick = 0; pendingVel = -1.0f; amp.hardReset(); filt.reset(); }

    inline float render() {
        if (!busy) return 0.0f;
        // Declick: fade the current tail to zero, then restart with the queued hit.
        float fade = 1.0f;
        if (declick > 0) {
            fade = static_cast<float>(declick) / kDeclick;
            if (--declick == 0) { float v = pendingVel >= 0 ? pendingVel : vel; start(v); return 0.0f; }
        }
        float a = amp.next();
        if (!amp.active()) { busy = false; return 0.0f; }
        float out = 0.0f;
        if (toneLevel > 0) {
            pitchEnv *= pDecay;
            osc.inc = (pEnd + (pStart - pEnd) * pitchEnv) / sr;
            float body = static_cast<float>(std::sin(osc.phase * kTwoPi));
            osc.phase += osc.inc; if (osc.phase >= 1.0) osc.phase -= 1.0;
            out += body * toneLevel;
        }
        if (noiseLevel > 0) {
            float n = noise.next();
            if (useFilt) n = filt.process(n, filtMode);
            out += n * noiseLevel;
        }
        return out * a * vel * level * fade;
    }
};

// ---- Master FX --------------------------------------------------------------
struct Delay {
    static constexpr int kMax = 96000 * 2;
    float bufL[kMax]; float bufR[kMax];
    int writeIdx = 0, samples = 12000;
    float feedback = 0.34f;
    void init(double sr, double bpm) {
        std::memset(bufL, 0, sizeof(bufL)); std::memset(bufR, 0, sizeof(bufR));
        setTempo(sr, bpm);
    }
    void setTempo(double sr, double bpm) {
        int s = static_cast<int>((60.0 / bpm) * sr / 2.0);   // 1/8 note
        samples = clampi(s, 1, kMax - 1);
    }
    inline void process(float inL, float inR, float &outL, float &outR) {
        int readIdx = writeIdx - samples; if (readIdx < 0) readIdx += kMax;
        float dl = bufL[readIdx], dr = bufR[readIdx];
        bufL[writeIdx] = flushDenorm(sanitize(inL) + dr * feedback);
        bufR[writeIdx] = flushDenorm(sanitize(inR) + dl * feedback);
        if (++writeIdx >= kMax) writeIdx = 0;
        outL += dl; outR += dr;
    }
};
struct Comb {
    float *buf; int size; int idx = 0; float fb; float store = 0;
    inline void process(float in, float &out) {
        float y = buf[idx];
        store = flushDenorm(y * 0.8f + store * 0.2f);
        buf[idx] = in + store * fb;
        if (++idx >= size) idx = 0;
        out += y;
    }
};
struct Allpass {
    float *buf; int size; int idx = 0;
    inline float process(float in) {
        float y = buf[idx]; float out = -in + y;
        buf[idx] = flushDenorm(in + y * 0.5f);
        if (++idx >= size) idx = 0;
        return out;
    }
};
struct Reverb {
    float combBuf[8][1700]; float apBuf[4][600];
    Comb combsL[4], combsR[4]; Allpass apL[2], apR[2];
    void init() {
        std::memset(combBuf, 0, sizeof(combBuf)); std::memset(apBuf, 0, sizeof(apBuf));
        const int cl[4] = {1116, 1188, 1277, 1356}, cr[4] = {1139, 1211, 1300, 1379};
        for (int i = 0; i < 4; ++i) { combsL[i] = {combBuf[i], cl[i], 0, 0.80f, 0}; combsR[i] = {combBuf[i + 4], cr[i], 0, 0.80f, 0}; }
        const int al[2] = {556, 441}, ar[2] = {579, 464};
        for (int i = 0; i < 2; ++i) { apL[i] = {apBuf[i], al[i], 0}; apR[i] = {apBuf[i + 2], ar[i], 0}; }
    }
    inline void process(float inL, float inR, float &outL, float &outR) {
        float in = (sanitize(inL) + sanitize(inR)) * 0.25f;
        float l = 0, r = 0;
        for (int i = 0; i < 4; ++i) { combsL[i].process(in, l); combsR[i].process(in, r); }
        for (int i = 0; i < 2; ++i) { l = apL[i].process(l); r = apR[i].process(r); }
        outL += l; outR += r;
    }
};
inline float softClip(float x) {
    if (x > 1.5f) x = 1.5f; else if (x < -1.5f) x = -1.5f;
    return x - (x * x * x) * (1.0f / 6.75f);
}

struct StepData { int16_t note; float vel; };

// ---- Built-in default patches (S1 bridge; Swift takes over in S2) -----------
void defaultPatch(int preset, ABPatch &p) {
    // Baseline
    std::memset(&p, 0, sizeof(p));
    p.osc1Wave = AB_WAVE_SAW; p.osc2Wave = AB_WAVE_SAW; p.oscMix = 0.0f;
    p.osc2Semi = 0; p.osc2Fine = 0; p.unison = 1; p.unisonDetune = 0; p.unisonWidth = 0;
    p.subLevel = 0.3f; p.noiseLevel = 0;
    p.filterType = AB_FILTER_LP; p.cutoff = 900; p.resonance = 0.35f; p.drive = 0.1f;
    p.envAmount = 0.55f; p.keyTrack = 0.4f;
    p.ampA = 0.003f; p.ampD = 0.25f; p.ampS = 0.0f; p.ampR = 0.15f;
    p.modA = 0.002f; p.modD = 0.18f; p.modS = 0.1f; p.modR = 0.12f;
    p.lfoShape = 0; p.lfoTarget = AB_LFO_OFF; p.lfoRateHz = 5.0f; p.lfoSync = 0; p.lfoDepth = 0;
    p.glide = 0; p.velAmount = 0.5f;
    p.gain = 0.8f; p.pan = 0; p.delaySend = 0.15f; p.reverbSend = 0.12f;

    switch (preset) {
        case AB_SYNTH_BASS:
            p.osc1Wave = AB_WAVE_SAW; p.subLevel = 0.85f; p.noiseLevel = 0;
            p.cutoff = 320; p.resonance = 0.45f; p.drive = 0.35f; p.envAmount = 0.35f; p.keyTrack = 0.2f;
            p.ampD = 0.20f; p.ampS = 0.55f; p.ampR = 0.10f;
            p.delaySend = 0.02f; p.reverbSend = 0.03f; p.gain = 0.9f;
            break;
        case AB_SYNTH_LEAD:
            p.unison = 5; p.unisonDetune = 18; p.unisonWidth = 0.8f;
            p.oscMix = 0.25f; p.osc2Semi = -12; p.subLevel = 0.15f;
            p.cutoff = 1400; p.resonance = 0.3f; p.drive = 0.2f; p.envAmount = 0.5f;
            p.ampA = 0.005f; p.ampD = 0.25f; p.ampS = 0.65f; p.ampR = 0.20f;
            p.lfoTarget = AB_LFO_PITCH; p.lfoRateHz = 5.5f; p.lfoDepth = 0.12f;
            p.delaySend = 0.28f; p.reverbSend = 0.2f;
            break;
        case AB_SYNTH_KEYS:
            p.osc1Wave = AB_WAVE_TRI; p.osc2Wave = AB_WAVE_SINE; p.oscMix = 0.35f;
            p.unison = 2; p.unisonDetune = 6; p.unisonWidth = 0.5f;
            p.subLevel = 0.2f; p.cutoff = 2400; p.resonance = 0.2f; p.envAmount = 0.3f;
            p.ampA = 0.002f; p.ampD = 0.35f; p.ampS = 0.4f; p.ampR = 0.30f;
            p.delaySend = 0.12f; p.reverbSend = 0.25f;
            break;
        default: /* AB_SYNTH_PLUCK */
            p.unison = 3; p.unisonDetune = 9; p.unisonWidth = 0.55f;
            p.subLevel = 0.25f; p.cutoff = 700; p.resonance = 0.4f; p.drive = 0.15f;
            p.envAmount = 0.7f;
            p.ampA = 0.002f; p.ampD = 0.16f; p.ampS = 0.0f; p.ampR = 0.12f;
            p.modD = 0.12f; p.modS = 0.0f;
            p.delaySend = 0.22f; p.reverbSend = 0.16f;
            break;
    }
}

// ---- A track (one layer) -----------------------------------------------------
struct Track {
    std::atomic<bool> active{false};
    std::atomic<bool> muted{false};
    std::atomic<bool> resetRequest{false};
    int kind = AB_KIND_SYNTH;
    int drumSound = AB_DRUM_KICK;

    // Patch mailbox: UI writes `staged`, sets dirty; audio thread swaps at
    // control-block boundaries into cfg.p and recomputes derived state.
    ABPatch staged;
    std::atomic<int> patchDirty{0};
    VoiceConfig cfg;

    SynthVoice synth[kVoicesPerTrack];
    DrumVoice drum;
    StepData steps[AB_MAX_PATTERNS][AB_NUM_STEPS];

    // Channel strip smoothers (audio-thread owned).
    Smooth gainS, panS;
    double lastNote = -1.0;   // for glide

    void init(float sr) {
        for (auto &v : synth) v.init(sr);
        drum.setType(AB_DRUM_KICK, sr);
        defaultPatch(AB_SYNTH_PLUCK, cfg.p);
        cfg.recompute();
        gainS.snap(cfg.p.gain); panS.snap(cfg.p.pan);
        clearAllPatterns();
    }
    void clearAllPatterns() {
        for (auto &pat : steps) for (auto &s : pat) s = {60, 0.0f};
    }
    SynthVoice *alloc() {
        for (auto &v : synth) if (!v.busy) return &v;
        // Steal the oldest = the voice with the smallest remaining envelope value.
        SynthVoice *steal = &synth[0];
        for (auto &v : synth) if (v.amp.value < steal->amp.value) steal = &v;
        return steal;
    }
    // Audio-thread control-block maintenance.
    inline void controlTick(double sr) {
        if (resetRequest.exchange(false, std::memory_order_acq_rel)) {
            for (auto &v : synth) v.hardReset();
            drum.hardReset();
            lastNote = -1.0;
        }
        if (patchDirty.exchange(0, std::memory_order_acq_rel)) {
            cfg.p = staged;
            cfg.recompute();
            gainS.target = clampf(cfg.p.gain, 0.0f, 1.5f);
            panS.target = clampf(cfg.p.pan, -1.0f, 1.0f);
            // Re-apply envelope rates to voices not currently sounding.
            for (auto &v : synth) if (!v.busy) v.applyEnvelopes(cfg.p);
        }
        gainS.tick(0.2f); panS.tick(0.2f);
        (void)sr;
    }
};

} // namespace

// ---- The engine ---------------------------------------------------------------
struct ABAudioCore {
    double sr = 44100.0;
    Track tracks[AB_MAX_TRACKS];
    Delay delay; Reverb reverb;

    std::atomic<double> bpm{112.0};
    std::atomic<int> playing{0};
    std::atomic<int> uiStep{-1};
    std::atomic<double> uiPos{-1.0};
    std::atomic<int> uiPattern{0};
    std::atomic<int> uiSongPos{-1};
    double samplesPerStep = 0.0, stepAccum = 0.0;
    int curStep = 0; bool lastPlaying = false;
    int ctrlCountdown = 0;

    std::atomic<int> editPattern{0};
    std::atomic<int> songModeFlag{0};
    std::atomic<int> songLen{0};
    int song[AB_MAX_SONG_LEN] = {0};
    int curPattern = 0, songPos = 0;

    void recomputeStepLen() {
        samplesPerStep = (60.0 / bpm.load(std::memory_order_relaxed)) * sr / 4.0;
    }
    void advancePattern(bool first) {
        const int len = songLen.load(std::memory_order_acquire);   // single load (audit: %0 fix)
        if (songModeFlag.load(std::memory_order_relaxed) && len > 0) {
            songPos = first ? 0 : (songPos + 1) % len;
            int idx = song[songPos];
            curPattern = (idx >= 0 && idx < AB_MAX_PATTERNS) ? idx : 0;
            uiSongPos.store(songPos, std::memory_order_relaxed);
        } else {
            curPattern = editPattern.load(std::memory_order_relaxed);
            uiSongPos.store(-1, std::memory_order_relaxed);
        }
        uiPattern.store(curPattern, std::memory_order_relaxed);
    }
    void triggerStep(int step) {
        int gate = static_cast<int>(samplesPerStep * 0.9);
        for (auto &t : tracks) {
            if (!t.active.load(std::memory_order_acquire)) continue;
            StepData &sd = t.steps[curPattern][step];
            if (sd.vel <= 0.0f) continue;
            if (t.kind == AB_KIND_SYNTH) {
                t.alloc()->noteOn(t.cfg, sd.note, sd.vel, gate, t.lastNote);
                t.lastNote = sd.note;
            } else {
                t.drum.trigger(sd.vel);
            }
        }
    }
};

extern "C" {

void ab_patch_init(ABPatch *out) {
    if (out) defaultPatch(AB_SYNTH_PLUCK, *out);
}

ABAudioCore *ab_core_create(double sampleRate) {
    auto *c = new (std::nothrow) ABAudioCore();
    if (!c) return nullptr;
    c->sr = sampleRate > 0 ? sampleRate : 44100.0;
    for (auto &t : c->tracks) { t.active.store(false); t.muted.store(false); t.init(static_cast<float>(c->sr)); }
    c->delay.init(c->sr, 112.0);
    c->reverb.init();
    c->recomputeStepLen();
    return c;
}

void ab_core_destroy(ABAudioCore *core) { delete core; }

void ab_core_set_tempo(ABAudioCore *core, double bpm) {
    if (!core) return;
    if (bpm < 20.0) bpm = 20.0; else if (bpm > 300.0) bpm = 300.0;
    core->bpm.store(bpm, std::memory_order_relaxed);
    core->recomputeStepLen();
    core->delay.setTempo(core->sr, bpm);
}

void ab_core_set_playing(ABAudioCore *core, int playing) {
    if (core) core->playing.store(playing ? 1 : 0, std::memory_order_relaxed);
}
int ab_core_current_step(ABAudioCore *core) { return core ? core->uiStep.load(std::memory_order_relaxed) : -1; }
double ab_core_play_position(ABAudioCore *core) { return core ? core->uiPos.load(std::memory_order_relaxed) : -1.0; }
int ab_core_current_pattern(ABAudioCore *core) { return core ? core->uiPattern.load(std::memory_order_relaxed) : 0; }
int ab_core_song_position(ABAudioCore *core) { return core ? core->uiSongPos.load(std::memory_order_relaxed) : -1; }

void ab_core_set_pattern(ABAudioCore *core, int pattern) {
    if (!core || pattern < 0 || pattern >= AB_MAX_PATTERNS) return;
    core->editPattern.store(pattern, std::memory_order_relaxed);
    // When stopped the render loop is idle, so publishing the UI mirror here is
    // safe; curPattern itself is picked up by advancePattern() at play start.
    if (!core->playing.load(std::memory_order_relaxed))
        core->uiPattern.store(pattern, std::memory_order_relaxed);
}

void ab_core_set_song(ABAudioCore *core, const int *seq, int len) {
    if (!core) return;
    if (len < 0) len = 0; else if (len > AB_MAX_SONG_LEN) len = AB_MAX_SONG_LEN;
    for (int i = 0; i < len; ++i) core->song[i] = (seq && seq[i] >= 0 && seq[i] < AB_MAX_PATTERNS) ? seq[i] : 0;
    core->songLen.store(len, std::memory_order_release);
}

void ab_core_set_song_mode(ABAudioCore *core, int on) {
    if (core) core->songModeFlag.store(on ? 1 : 0, std::memory_order_relaxed);
}

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
        t.clearAllPatterns();
        t.muted.store(false, std::memory_order_relaxed);
        t.kind = kind == AB_KIND_DRUM ? AB_KIND_DRUM : AB_KIND_SYNTH;
        // Track is inactive (render skips it), so touching voices/config here is
        // race-free. Reset synchronously — an async resetRequest would be consumed
        // by the first control tick and kill notes triggered before rendering.
        for (auto &v : t.synth) v.hardReset();
        t.drum.hardReset();
        t.lastNote = -1.0;
        t.resetRequest.store(false, std::memory_order_relaxed);
        if (t.kind == AB_KIND_DRUM) {
            t.drumSound = sound;
            t.drum.setType(sound, static_cast<float>(core->sr));
        } else {
            defaultPatch(sound, t.staged);
            t.cfg.p = t.staged;
            t.cfg.recompute();
            t.gainS.snap(clampf(t.cfg.p.gain, 0.0f, 1.5f));
            t.panS.snap(clampf(t.cfg.p.pan, -1.0f, 1.0f));
            t.patchDirty.store(0, std::memory_order_relaxed);
        }
        t.active.store(true, std::memory_order_release);
        return i;
    }
    return -1;
}

void ab_core_remove_track(ABAudioCore *core, int track) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS) return;
    core->tracks[track].resetRequest.store(true, std::memory_order_release);
    core->tracks[track].active.store(false, std::memory_order_release);
}

void ab_core_clear_track(ABAudioCore *core, int track, int pattern) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS || pattern < 0 || pattern >= AB_MAX_PATTERNS) return;
    for (auto &s : core->tracks[track].steps[pattern]) s.vel = 0.0f;
}

void ab_core_set_track_sound(ABAudioCore *core, int track, int sound) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS) return;
    Track &t = core->tracks[track];
    if (t.kind == AB_KIND_DRUM) {
        t.drumSound = sound;
        t.drum.setType(sound, static_cast<float>(core->sr));   // acceptable UI-thread touch: params only
    } else {
        defaultPatch(sound, t.staged);
        t.patchDirty.store(1, std::memory_order_release);
    }
}

void ab_core_set_patch(ABAudioCore *core, int track, const ABPatch *patch) {
    if (!core || !patch || track < 0 || track >= AB_MAX_TRACKS) return;
    Track &t = core->tracks[track];
    if (t.kind != AB_KIND_SYNTH) return;
    t.staged = *patch;
    t.patchDirty.store(1, std::memory_order_release);
}

void ab_core_set_track_mute(ABAudioCore *core, int track, int muted) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS) return;
    core->tracks[track].muted.store(muted ? true : false, std::memory_order_relaxed);
}

void ab_core_set_step(ABAudioCore *core, int track, int pattern, int step, int midiNote, int velocity) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS || step < 0 || step >= AB_NUM_STEPS
        || pattern < 0 || pattern >= AB_MAX_PATTERNS) return;
    midiNote = clampi(midiNote, 0, 127);        // audit: unbounded note -> NaN
    velocity = clampi(velocity, 0, 127);
    core->tracks[track].steps[pattern][step].note = static_cast<int16_t>(midiNote);
    core->tracks[track].steps[pattern][step].vel = velocity / 127.0f;
}

void ab_core_note_on(ABAudioCore *core, int track, int midiNote, float velocity) {
    if (!core || track < 0 || track >= AB_MAX_TRACKS) return;
    Track &t = core->tracks[track];
    if (!t.active.load(std::memory_order_acquire)) return;
    midiNote = clampi(midiNote, 0, 127);
    if (t.kind == AB_KIND_SYNTH) {
        t.alloc()->noteOn(t.cfg, midiNote, clampf(velocity, 0, 1), static_cast<int>(core->sr * 0.4), t.lastNote);
        t.lastNote = midiNote;
    } else {
        t.drum.trigger(clampf(velocity, 0, 1));
    }
}

void ab_core_render(ABAudioCore *core, float *left, float *right, int frames) {
    if (!core || !left || !right) return;
    const bool isPlaying = core->playing.load(std::memory_order_relaxed) != 0;
    const double bpm = core->bpm.load(std::memory_order_relaxed);

    if (isPlaying && !core->lastPlaying) {
        core->curStep = 0; core->stepAccum = 0.0;
        core->advancePattern(true);
        core->triggerStep(0); core->uiStep.store(0, std::memory_order_relaxed);
    } else if (!isPlaying && core->lastPlaying) {
        core->uiStep.store(-1, std::memory_order_relaxed);
        core->uiPos.store(-1.0, std::memory_order_relaxed);
        core->uiSongPos.store(-1, std::memory_order_relaxed);
    }
    core->lastPlaying = isPlaying;

    for (int i = 0; i < frames; ++i) {
        if (isPlaying) {
            core->stepAccum += 1.0;
            if (core->stepAccum >= core->samplesPerStep) {
                core->stepAccum -= core->samplesPerStep;
                if (core->stepAccum >= core->samplesPerStep)      // audit: tempo-jump machine-gun
                    core->stepAccum = 0.0;
                core->curStep = (core->curStep + 1) % AB_NUM_STEPS;
                if (core->curStep == 0) core->advancePattern(false);
                core->triggerStep(core->curStep);
                core->uiStep.store(core->curStep, std::memory_order_relaxed);
            }
        }

        // Control-rate maintenance for all tracks.
        if (core->ctrlCountdown-- <= 0) {
            core->ctrlCountdown = kCtrlBlock - 1;
            for (auto &t : core->tracks) {
                if (t.active.load(std::memory_order_acquire)) t.controlTick(core->sr);
            }
        }

        float dryL = 0, dryR = 0, dSendL = 0, dSendR = 0, rSendL = 0, rSendR = 0;

        for (auto &t : core->tracks) {
            if (!t.active.load(std::memory_order_acquire) || t.muted.load(std::memory_order_relaxed)) continue;
            float tl = 0, tr = 0;
            if (t.kind == AB_KIND_SYNTH) {
                for (auto &v : t.synth) v.render(t.cfg, bpm, tl, tr);
                tl *= 0.6f; tr *= 0.6f;   // voice-sum headroom
            } else {
                float m = t.drum.render();
                tl = m; tr = m;
            }
            // Channel strip: smoothed gain + equal-power pan (center = unity).
            float g = t.gainS.v;
            float pa = (t.panS.v + 1.0f) * 0.25f * static_cast<float>(kPi);
            tl *= g * std::cos(pa) * 1.41421356f;
            tr *= g * std::sin(pa) * 1.41421356f;
            dryL += tl; dryR += tr;
            float ds = t.kind == AB_KIND_SYNTH ? t.cfg.p.delaySend : 0.10f;
            float rs = t.kind == AB_KIND_SYNTH ? t.cfg.p.reverbSend : 0.12f;
            dSendL += tl * ds; dSendR += tr * ds;
            rSendL += tl * rs; rSendR += tr * rs;
        }

        float outL = dryL, outR = dryR;
        core->delay.process(dSendL, dSendR, outL, outR);
        core->reverb.process(rSendL, rSendR, outL, outR);

        left[i] = softClip(sanitize(outL) * 0.7f);
        right[i] = softClip(sanitize(outR) * 0.7f);
    }

    if (isPlaying && core->samplesPerStep > 0.0)
        core->uiPos.store(core->curStep + core->stepAccum / core->samplesPerStep, std::memory_order_relaxed);
}

const char *ab_core_version(void) { return "Absound DSP 0.4.0 (engine v2 — stereo patches)"; }

} // extern "C"
