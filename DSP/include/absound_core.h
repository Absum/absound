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
    AB_NUM_STEPS    = 16,
    AB_MAX_TRACKS   = 16,
    AB_MAX_PATTERNS = 8,
    AB_MAX_SONG_LEN = 64
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

/* ---------------------------------------------------------------------------
 * Synth patch — the complete description of one melodic sound.
 * Flat POD so it crosses the Swift bridge and stays ABI-stable. Applied at a
 * control-rate block boundary on the audio thread (staged copy), so live
 * editing while playing is click-free and race-safe.
 * ------------------------------------------------------------------------- */
enum { AB_WAVE_SAW = 0, AB_WAVE_SQUARE = 1, AB_WAVE_TRI = 2, AB_WAVE_SINE = 3 };
enum { AB_FILTER_LP = 0, AB_FILTER_BP = 1, AB_FILTER_HP = 2 };
enum { AB_LFO_OFF = 0, AB_LFO_PITCH = 1, AB_LFO_CUTOFF = 2, AB_LFO_AMP = 3, AB_LFO_PAN = 4 };
enum { AB_MAX_UNISON = 7 };

typedef struct ABPatch {
    /* Oscillators */
    int   osc1Wave, osc2Wave;      /* AB_WAVE_* */
    float oscMix;                  /* 0 = only osc1 .. 1 = only osc2 */
    int   osc2Semi;                /* -24..24 semitones */
    float osc2Fine;                /* -50..50 cents */
    int   unison;                  /* 1..AB_MAX_UNISON voices on osc1 */
    float unisonDetune;            /* 0..50 cents max spread */
    float unisonWidth;             /* 0..1 stereo spread of the unison fan */
    float subLevel;                /* 0..1 sine sub, -1 octave */
    float noiseLevel;              /* 0..1 */
    /* Filter */
    int   filterType;              /* AB_FILTER_* */
    float cutoff;                  /* 20..18000 Hz base */
    float resonance;               /* 0..1 */
    float drive;                   /* 0..1 tanh drive before the filter */
    float envAmount;               /* -1..1, scaled to +-8000 Hz */
    float keyTrack;                /* 0..1 */
    /* Envelopes (seconds; sustain 0..1) */
    float ampA, ampD, ampS, ampR;
    float modA, modD, modS, modR;
    /* LFO */
    int   lfoShape;                /* 0 sine, 1 tri, 2 sample&hold */
    int   lfoTarget;               /* AB_LFO_* */
    float lfoRateHz;               /* free rate when lfoSync == 0 */
    int   lfoSync;                 /* 0 free; N => period = 4/N beats (1=bar, 4=beat, 8=1/8th) */
    float lfoDepth;                /* 0..1 */
    /* Voice / output */
    float glide;                   /* 0..0.5 s portamento */
    float velAmount;               /* 0..1 velocity -> amp & cutoff */
    float gain;                    /* 0..1.5 channel gain */
    float pan;                     /* -1..1 */
    float delaySend, reverbSend;   /* 0..1 */
} ABPatch;

/* Fill a patch with sane defaults (a plain single-osc pluck). */
void ab_patch_init(ABPatch *out);

/* Lifecycle. */
ABAudioCore *ab_core_create(double sampleRate);
void ab_core_destroy(ABAudioCore *core);

/* Transport. */
void ab_core_set_tempo(ABAudioCore *core, double bpm);      /* clamped 20..300 */
void ab_core_set_playing(ABAudioCore *core, int playing);   /* 0 = stop, !=0 = play */
int  ab_core_current_step(ABAudioCore *core);               /* 0..AB_NUM_STEPS-1, -1 if stopped */
double ab_core_play_position(ABAudioCore *core);            /* continuous 0..AB_NUM_STEPS, -1 if stopped */

/* Patterns & song. A pattern is one 16-step loop of all tracks' step data.
 * Edit mode loops a single pattern (set_pattern); song mode plays a sequence. */
void ab_core_set_pattern(ABAudioCore *core, int pattern);            /* which pattern edit-mode loops */
void ab_core_set_song(ABAudioCore *core, const int *seq, int len);   /* sequence of pattern indices */
void ab_core_set_song_mode(ABAudioCore *core, int on);               /* 0 = loop one pattern, !=0 = play song */
int  ab_core_current_pattern(ABAudioCore *core);                     /* pattern index currently sounding */
int  ab_core_song_position(ABAudioCore *core);                       /* index into the song sequence, -1 if not song-playing */

/* Tracks. add returns the new track index, or -1 if the pool is full. */
int  ab_core_track_count(ABAudioCore *core);
int  ab_core_add_track(ABAudioCore *core, int kind, int sound);
void ab_core_remove_track(ABAudioCore *core, int track);
void ab_core_clear_track(ABAudioCore *core, int track, int pattern);
void ab_core_set_track_sound(ABAudioCore *core, int track, int sound); /* synth preset or drum type */
void ab_core_set_track_mute(ABAudioCore *core, int track, int muted);
/* Solo: when any track is soloed, only soloed tracks sound (mute still applies). */
void ab_core_set_track_solo(ABAudioCore *core, int track, int soloed);

/* Apply a full synth patch to a track (synth tracks only; ignored for drums).
 * Staged and swapped in on the audio thread at the next control block. */
void ab_core_set_patch(ABAudioCore *core, int track, const ABPatch *patch);

/* Pattern editing. velocity 0 clears the step; 1..127 enables it. For drum tracks
 * midiNote is ignored. */
void ab_core_set_step(ABAudioCore *core, int track, int pattern, int step, int midiNote, int velocity);

/* Live one-shot trigger (Highway/keyboard). */
void ab_core_note_on(ABAudioCore *core, int track, int midiNote, float velocity);

/* Render `frames` stereo samples into non-interleaved L/R buffers (overwrites). */
void ab_core_render(ABAudioCore *core, float *left, float *right, int frames);

const char *ab_core_version(void);

#ifdef __cplusplus
}
#endif

#endif /* ABSOUND_CORE_H */
