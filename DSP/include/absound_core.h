/*
 * Absound DSP core — real-time audio engine (N-track synth + drums + FX + sequencer).
 *
 * Portable C/C++ behind a flat C ABI so it imports cleanly into Swift via the
 * bridging header. Keep this header free of C++ types.
 *
 * Tracks are allocated from a fixed preallocated pool (no audio-thread allocation).
 * Each track is either a melodic SYNTH (its own polyphonic voice pool + preset)
 * or a DRUM (one percussion voice of a chosen type). The engine owns a master FX
 * chain and a sample-accurate step sequencer advanced from inside ab_core_render().
 */
#ifndef ABSOUND_CORE_H
#define ABSOUND_CORE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    AB_NUM_STEPS  = 16,
    AB_MAX_TRACKS = 16
};

/* Track kinds. */
enum {
    AB_KIND_SYNTH = 0,
    AB_KIND_DRUM  = 1
};

/* Synth presets (the `sound` of a synth track). */
enum {
    AB_SYNTH_PLUCK = 0,
    AB_SYNTH_BASS  = 1,
    AB_SYNTH_LEAD  = 2,
    AB_SYNTH_KEYS  = 3
};

/* Drum voices (the `sound` of a drum track). */
enum {
    AB_DRUM_KICK   = 0,
    AB_DRUM_SNARE  = 1,
    AB_DRUM_HAT    = 2,   /* closed hat */
    AB_DRUM_OPENHAT = 3,
    AB_DRUM_CLAP   = 4,
    AB_DRUM_TOM    = 5,
    AB_DRUM_RIM    = 6,
    AB_DRUM_PERC   = 7
};

typedef struct ABAudioCore ABAudioCore;

/* Lifecycle. */
ABAudioCore *ab_core_create(double sampleRate);
void ab_core_destroy(ABAudioCore *core);

/* Transport. */
void ab_core_set_tempo(ABAudioCore *core, double bpm);      /* clamped 20..300 */
void ab_core_set_playing(ABAudioCore *core, int playing);   /* 0 = stop, !=0 = play */
int  ab_core_current_step(ABAudioCore *core);               /* 0..AB_NUM_STEPS-1, -1 if stopped */
double ab_core_play_position(ABAudioCore *core);            /* continuous 0..AB_NUM_STEPS, -1 if stopped */

/* Tracks. add returns the new track index, or -1 if the pool is full. */
int  ab_core_track_count(ABAudioCore *core);
int  ab_core_add_track(ABAudioCore *core, int kind, int sound);
void ab_core_remove_track(ABAudioCore *core, int track);
void ab_core_clear_track(ABAudioCore *core, int track);
void ab_core_clear_all(ABAudioCore *core);
void ab_core_set_track_sound(ABAudioCore *core, int track, int sound); /* synth preset or drum type */
void ab_core_set_track_mute(ABAudioCore *core, int track, int muted);

/* Pattern editing. velocity 0 clears the step; 1..127 enables it. For drum tracks
 * midiNote is ignored. */
void ab_core_set_step(ABAudioCore *core, int track, int step, int midiNote, int velocity);

/* Live one-shot trigger (Highway/keyboard). */
void ab_core_note_on(ABAudioCore *core, int track, int midiNote, float velocity);

/* Render `frames` stereo samples into non-interleaved L/R buffers (overwrites). */
void ab_core_render(ABAudioCore *core, float *left, float *right, int frames);

const char *ab_core_version(void);

#ifdef __cplusplus
}
#endif

#endif /* ABSOUND_CORE_H */
