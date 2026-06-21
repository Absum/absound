/*
 * Absound DSP core — synth voice (stub implementation).
 * See absound_synth.h. Real engine lands in M1.
 */
#include "absound_synth.h"

#include <cmath>
#include <cstdlib>
#include <new>

namespace {
constexpr double kTwoPi = 6.283185307179586;

// MIDI note -> frequency (A4 = note 69 = 440 Hz).
inline double midiToHz(int note) {
    return 440.0 * std::pow(2.0, (static_cast<double>(note) - 69.0) / 12.0);
}
}  // namespace

struct ABSynthVoice {
    double sampleRate = 44100.0;
    double phase = 0.0;       // 0..1
    double phaseInc = 0.0;    // cycles per sample
    float velocity = 0.0f;
    float env = 0.0f;         // current amplitude envelope 0..1
    bool gateOpen = false;    // true between note_on and note_off

    // Crude linear attack/release (seconds). Replaced by ADSR in M1.
    float attackPerSample = 0.0f;
    float releasePerSample = 0.0f;
};

ABSynthVoice *ab_synth_create(double sampleRate) {
    auto *v = new (std::nothrow) ABSynthVoice();
    if (!v) return nullptr;
    v->sampleRate = sampleRate > 0.0 ? sampleRate : 44100.0;
    v->attackPerSample = static_cast<float>(1.0 / (0.005 * v->sampleRate));   // ~5 ms
    v->releasePerSample = static_cast<float>(1.0 / (0.120 * v->sampleRate));  // ~120 ms
    return v;
}

void ab_synth_destroy(ABSynthVoice *voice) {
    delete voice;
}

void ab_synth_note_on(ABSynthVoice *voice, int midiNote, float velocity) {
    if (!voice) return;
    if (midiNote < 0) midiNote = 0;
    if (midiNote > 127) midiNote = 127;
    voice->phaseInc = midiToHz(midiNote) / voice->sampleRate;
    voice->velocity = velocity < 0.0f ? 0.0f : (velocity > 1.0f ? 1.0f : velocity);
    voice->gateOpen = true;
}

void ab_synth_note_off(ABSynthVoice *voice) {
    if (!voice) return;
    voice->gateOpen = false;
}

void ab_synth_render(ABSynthVoice *voice, float *out, size_t count) {
    if (!voice || !out) return;
    for (size_t i = 0; i < count; ++i) {
        // Envelope: linear toward 1 while gated, toward 0 once released.
        const float target = voice->gateOpen ? 1.0f : 0.0f;
        const float step = voice->gateOpen ? voice->attackPerSample : voice->releasePerSample;
        if (voice->env < target) {
            voice->env += step;
            if (voice->env > target) voice->env = target;
        } else if (voice->env > target) {
            voice->env -= step;
            if (voice->env < target) voice->env = target;
        }

        const float sample =
            static_cast<float>(std::sin(voice->phase * kTwoPi)) * voice->env * voice->velocity;
        out[i] = sample;

        voice->phase += voice->phaseInc;
        if (voice->phase >= 1.0) voice->phase -= 1.0;
    }
}

const char *ab_synth_version(void) {
    return "Absound DSP 0.1.0 (M0 stub)";
}
