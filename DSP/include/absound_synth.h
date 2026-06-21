/*
 * Absound DSP core — synth voice (stub).
 *
 * Portable C/C++ with a flat C ABI so it can be shared verbatim between the iOS
 * app (via the Swift bridging header) and any future platform build. Keep this
 * header free of C++ types so it stays importable from Swift.
 *
 * M0 ships a minimal sine voice with a crude attack/release envelope purely to
 * prove the Swift<->C++ pipeline compiles and links. The real engine
 * (PolyBLEP oscillators, ADSR, state-variable filter, FX) arrives in M1.
 */
#ifndef ABSOUND_SYNTH_H
#define ABSOUND_SYNTH_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ABSynthVoice ABSynthVoice;

/* Create a monophonic voice for the given sample rate (Hz). Caller owns it. */
ABSynthVoice *ab_synth_create(double sampleRate);

/* Free a voice created by ab_synth_create. Safe to pass NULL. */
void ab_synth_destroy(ABSynthVoice *voice);

/* Trigger a note. midiNote 0..127, velocity 0..1. */
void ab_synth_note_on(ABSynthVoice *voice, int midiNote, float velocity);

/* Release the current note (enters the release stage). */
void ab_synth_note_off(ABSynthVoice *voice);

/* Render `count` mono float samples into `out` (overwrites). */
void ab_synth_render(ABSynthVoice *voice, float *out, size_t count);

/* Human-readable core version string (static storage; do not free). */
const char *ab_synth_version(void);

#ifdef __cplusplus
}
#endif

#endif /* ABSOUND_SYNTH_H */
