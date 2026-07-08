// Offline preview: render through the real DSP core to a stereo WAV so the
// engine can be auditioned without the app.
//
// Modes:
//   render_demo demo <out.wav> [seconds]           — the demo groove (beat + bass + lead)
//   render_demo preset <0-3> <out.wav> [seconds]   — one synth preset playing a riff, solo
//
// Build from the repo root:
//   clang++ -std=c++17 -O2 tools/AudioPreview/render_demo.cpp DSP/src/absound_core.cpp \
//           -I DSP/include -o /tmp/render_demo

#include "absound_core.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static void writeWav(const char *path, const std::vector<float> &l, const std::vector<float> &r, int sr) {
    const uint32_t frames = static_cast<uint32_t>(l.size());
    const uint16_t channels = 2, bits = 16;
    const uint32_t byteRate = sr * channels * bits / 8;
    const uint16_t blockAlign = channels * bits / 8;
    const uint32_t dataBytes = frames * blockAlign;

    FILE *f = std::fopen(path, "wb");
    if (!f) { std::perror("fopen"); return; }
    auto u32 = [&](uint32_t v) { std::fwrite(&v, 4, 1, f); };
    auto u16 = [&](uint16_t v) { std::fwrite(&v, 2, 1, f); };
    std::fwrite("RIFF", 1, 4, f); u32(36 + dataBytes); std::fwrite("WAVE", 1, 4, f);
    std::fwrite("fmt ", 1, 4, f); u32(16); u16(1); u16(channels);
    u32(sr); u32(byteRate); u16(blockAlign); u16(bits);
    std::fwrite("data", 1, 4, f); u32(dataBytes);
    for (uint32_t i = 0; i < frames; ++i) {
        auto clip = [](float x) { return x < -1 ? -1.f : (x > 1 ? 1.f : x); };
        int16_t sl = static_cast<int16_t>(clip(l[i]) * 32767.0f);
        int16_t sr16 = static_cast<int16_t>(clip(r[i]) * 32767.0f);
        std::fwrite(&sl, 2, 1, f); std::fwrite(&sr16, 2, 1, f);
    }
    std::fclose(f);
    std::printf("Wrote %s — %.1fs, %d Hz stereo\n", path, double(frames) / sr, sr);
}

static void renderTo(ABAudioCore *core, double seconds, int sr,
                     std::vector<float> &outL, std::vector<float> &outR) {
    const int total = static_cast<int>(seconds * sr), block = 512;
    outL.reserve(total); outR.reserve(total);
    std::vector<float> bl(block), br(block);
    int done = 0;
    while (done < total) {
        int frames = std::min(block, total - done);
        ab_core_render(core, bl.data(), br.data(), frames);
        for (int i = 0; i < frames; ++i) { outL.push_back(bl[i]); outR.push_back(br[i]); }
        done += frames;
    }
}

int main(int argc, char **argv) {
    const int sr = 44100;
    const char *mode = argc > 1 ? argv[1] : "demo";

    ABAudioCore *core = ab_core_create(sr);
    ab_core_set_tempo(core, 112);
    std::vector<float> L, R;

    if (std::strcmp(mode, "fx") == 0 && argc > 3) {
        // One effect at showcase settings on a sustained riff:  fx <type 1..13> <out> [secs]
        int type = std::atoi(argv[2]);
        const char *out = argv[3];
        double seconds = argc > 4 ? std::atof(argv[4]) : 6.0;

        int t = ab_core_add_track(core, AB_KIND_SYNTH, AB_SYNTH_KEYS);
        const int riff[][3] = {{0, 48, 112}, {4, 55, 104}, {8, 60, 112}, {12, 55, 100}};
        for (auto &n : riff) ab_core_set_step(core, t, 0, n[0], n[1], n[2]);

        ABFXChain chain; ab_fx_chain_init(&chain);
        chain.slots[0].type = type;
        switch (type) {   // showcase params
            case AB_FX_DRIVE: chain.slots[0] = {type, 1, 0.8f, 0, 0.6f, 1.0f}; break;
            case AB_FX_CRUSH: chain.slots[0] = {type, 1, 6, 8, 1.0f, 0}; break;
            case AB_FX_CHORUS: chain.slots[0] = {type, 1, 0.8f, 0.8f, 0.7f, 0.2f}; break;
            case AB_FX_PHASER: chain.slots[0] = {type, 1, 0.5f, 0.9f, 0.6f, 0.9f}; break;
            case AB_FX_EQ: chain.slots[0] = {type, 1, -12, 6, 8, 1200}; break;
            case AB_FX_COMP: chain.slots[0] = {type, 1, 0.15f, 8, 0.15f, 1.5f}; break;
            case AB_FX_TREMPAN: chain.slots[0] = {type, 1, 8, 1.0f, 0.7f, 0}; break;
            case AB_FX_WIDTH: chain.slots[0] = {type, 1, 2.0f, 120, 0, 0}; break;
            case AB_FX_DELAY: chain.slots[0] = {type, 1, 8, 0.6f, 0.6f, 0.6f}; break;
            case AB_FX_RINGMOD: chain.slots[0] = {type, 1, 330, 0.8f, 0.8f, 0}; break;
            case AB_FX_GATE: chain.slots[0] = {type, 1, 16, 4, 1.0f, 3}; break;
            case AB_FX_WAH: chain.slots[0] = {type, 1, 0.9f, 0.9f, 0.8f, 1.0f}; break;
            case AB_FX_ROOM: chain.slots[0] = {type, 1, 0.9f, 0.3f, 0.6f, 10}; break;
            default: break;
        }
        ab_core_set_fx(core, t, &chain);
        ab_core_set_playing(core, 1);
        renderTo(core, seconds, sr, L, R);
        writeWav(out, L, R, sr);
    } else if (std::strcmp(mode, "preset") == 0 && argc > 3) {
        // Solo preset audition: a melodic riff on one synth track, pattern 0.
        int preset = std::atoi(argv[2]);
        const char *out = argv[3];
        double seconds = argc > 4 ? std::atof(argv[4]) : 8.0;

        int t = ab_core_add_track(core, AB_KIND_SYNTH, preset);
        // C minor riff spanning an octave, some sustained gaps.
        const int riff[][3] = {  /* step, note, vel */
            {0, 48, 110}, {3, 51, 96}, {6, 55, 104}, {8, 60, 112},
            {10, 58, 90}, {12, 55, 100}, {14, 51, 96}
        };
        for (auto &n : riff) ab_core_set_step(core, t, 0, n[0], n[1], n[2]);
        ab_core_set_playing(core, 1);
        renderTo(core, seconds, sr, L, R);
        writeWav(out, L, R, sr);
    } else {
        const char *out = argc > 2 ? argv[2] : "/tmp/absound_demo.wav";
        double seconds = argc > 3 ? std::atof(argv[3]) : 8.0;

        int kick = ab_core_add_track(core, AB_KIND_DRUM, AB_DRUM_KICK);
        int snare = ab_core_add_track(core, AB_KIND_DRUM, AB_DRUM_SNARE);
        int hat = ab_core_add_track(core, AB_KIND_DRUM, AB_DRUM_HAT);
        int bass = ab_core_add_track(core, AB_KIND_SYNTH, AB_SYNTH_BASS);
        int lead = ab_core_add_track(core, AB_KIND_SYNTH, AB_SYNTH_LEAD);

        for (int s : {0, 4, 8, 11}) ab_core_set_step(core, kick, 0, s, 0, 120);
        for (int s : {4, 12}) ab_core_set_step(core, snare, 0, s, 0, 112);
        for (int s = 0; s < AB_NUM_STEPS; ++s) ab_core_set_step(core, hat, 0, s, 0, s % 2 == 0 ? 60 : 95);
        for (auto &n : {std::pair<int,int>{0, 36}, {8, 36}, {11, 39}})
            ab_core_set_step(core, bass, 0, n.first, n.second, 110);
        const int riff[][2] = {{0, 60}, {3, 63}, {6, 67}, {8, 70}, {10, 67}, {13, 63}, {14, 65}};
        for (auto &n : riff) ab_core_set_step(core, lead, 0, n[0], n[1], 105);

        ab_core_set_playing(core, 1);
        renderTo(core, seconds, sr, L, R);
        writeWav(out, L, R, sr);
    }

    ab_core_destroy(core);
    return 0;
}
