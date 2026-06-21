// Offline preview: render the M1 demo pattern through the real DSP core to a WAV
// so the engine can be auditioned without the app. Mirrors the seed pattern in
// TransportController.seedDemoPattern().
//
// Build & run from the repo root:
//   clang++ -std=c++17 -O2 tools/AudioPreview/render_demo.cpp DSP/src/absound_core.cpp \
//           -I DSP/include -o /tmp/render_demo
//   /tmp/render_demo /tmp/absound_demo.wav [seconds]

#include "absound_core.h"

#include <cstdint>
#include <cstdio>
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

int main(int argc, char **argv) {
    const char *out = argc > 1 ? argv[1] : "/tmp/absound_demo.wav";
    const double seconds = argc > 2 ? atof(argv[2]) : 8.0;
    const int sr = 44100;

    ABAudioCore *core = ab_core_create(sr);
    ab_core_set_tempo(core, 112);

    auto step = [&](int track, int s, int note, int vel) { ab_core_set_step(core, track, s, note, vel); };
    for (int s : {0, 4, 8, 11}) step(AB_TRACK_KICK, s, 0, 120);
    for (int s : {4, 12}) step(AB_TRACK_SNARE, s, 0, 112);
    for (int s = 0; s < AB_NUM_STEPS; ++s) step(AB_TRACK_HAT, s, 0, s % 2 == 0 ? 60 : 95);
    const int riff[][2] = {{0, 60}, {3, 63}, {6, 67}, {8, 70}, {10, 67}, {13, 63}, {14, 65}};
    for (auto &n : riff) step(AB_TRACK_SYNTH, n[0], n[1], 105);

    ab_core_set_playing(core, 1);

    const int total = int(seconds * sr), block = 512;
    std::vector<float> outL, outR; outL.reserve(total); outR.reserve(total);
    std::vector<float> bl(block), br(block);
    int done = 0;
    while (done < total) {
        int frames = std::min(block, total - done);
        ab_core_render(core, bl.data(), br.data(), frames);
        for (int i = 0; i < frames; ++i) { outL.push_back(bl[i]); outR.push_back(br[i]); }
        done += frames;
    }
    ab_core_destroy(core);

    writeWav(out, outL, outR, sr);
    return 0;
}
