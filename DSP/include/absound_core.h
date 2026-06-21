/*
 * Absound DSP core — real-time audio engine (synth + drums + FX + sequencer).
 *
 * Portable C/C++ behind a flat C ABI so it imports cleanly into Swift via the
 * bridging header and stays reusable on other platforms. Keep this header free
 * of C++ types.
 *
 * The engine owns synthesis, a master FX chain, and a sample-accurate step
 * sequencer that is advanced from inside ab_core_render() — so timing is locked
 * to the audio clock, never to a UI timer.
 */
#ifndef ABSOUND_CORE_H
#define ABSOUND_CORE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Fixed track layout for M1. Track 0 is the melodic synth; 1..3 are drums. */
enum {
    AB_TRACK_SYNTH = 0,
    AB_TRACK_KICK  = 1,
    AB_TRACK_SNARE = 2,
    AB_TRACK_HAT   = 3,
    AB_NUM_TRACKS  = 4,
    AB_NUM_STEPS   = 16
};

typedef struct ABAudioCore ABAudioCore;

/* Lifecycle. Caller owns the result; destroy is NULL-safe. */
ABAudioCore *ab_core_create(double sampleRate);
void ab_core_destroy(ABAudioCore *core);

/* Transport. */
void ab_core_set_tempo(ABAudioCore *core, double bpm);      /* clamped 20..300 */
void ab_core_set_playing(ABAudioCore *core, int playing);   /* 0 = stop, !=0 = play */
int  ab_core_current_step(ABAudioCore *core);               /* 0..AB_NUM_STEPS-1, -1 if stopped */

/* Pattern editing. velocity 0 clears the step; 1..127 enables it. For drum
 * tracks midiNote is ignored (each drum has a fixed character). */
void ab_core_set_step(ABAudioCore *core, int track, int step, int midiNote, int velocity);
void ab_core_clear(ABAudioCore *core);

/* Live one-shot trigger (used later by Highway/keyboard input). */
void ab_core_note_on(ABAudioCore *core, int track, int midiNote, float velocity);

/* Render `frames` stereo samples into non-interleaved L/R buffers (overwrites). */
void ab_core_render(ABAudioCore *core, float *left, float *right, int frames);

/* Static version string (do not free). */
const char *ab_core_version(void);

#ifdef __cplusplus
}
#endif

#endif /* ABSOUND_CORE_H */
