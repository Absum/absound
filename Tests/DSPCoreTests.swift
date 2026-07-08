//
//  DSPCoreTests.swift
//  Engine tests for the N-track core: track management + offline render behaves
//  (signal present, finite, in range, sequencer steps).
//

import XCTest

final class DSPCoreTests: XCTestCase {

    private let sr = 44_100.0
    private let block = 512

    private func addTrack(_ core: OpaquePointer?, kind: Int, sound: Int) -> Int {
        Int(ab_core_add_track(core, Int32(kind), Int32(sound)))
    }
    private func setStep(_ core: OpaquePointer?, _ track: Int, _ step: Int, _ note: Int, _ vel: Int, pattern: Int = 0) {
        ab_core_set_step(core, Int32(track), Int32(pattern), Int32(step), Int32(note), Int32(vel))
    }

    private func renderMetrics(_ core: OpaquePointer?, seconds: Double) -> (peak: Float, rms: Double, finite: Bool) {
        let total = Int(seconds * sr)
        var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
        var peak: Float = 0, sumSq = 0.0, n = 0, done = 0
        var finite = true
        while done < total {
            let frames = min(block, total - done)
            ab_core_render(core, &l, &r, Int32(frames))
            for i in 0..<frames {
                let s = l[i]
                if !s.isFinite { finite = false }
                peak = max(peak, abs(s)); sumSq += Double(s) * Double(s); n += 1
            }
            done += frames
        }
        return (peak, (n > 0 ? (sumSq / Double(n)).squareRoot() : 0), finite)
    }

    func testVersionExposed() {
        XCTAssertTrue(String(cString: ab_core_version()).contains("Absound"))
    }

    func testTrackManagement() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        XCTAssertEqual(ab_core_track_count(core), 0)
        let kick = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        let synth = addTrack(core, kind: AB_KIND_SYNTH, sound: AB_SYNTH_LEAD)
        XCTAssertGreaterThanOrEqual(kick, 0)
        XCTAssertGreaterThanOrEqual(synth, 0)
        XCTAssertEqual(ab_core_track_count(core), 2)
        ab_core_remove_track(core, Int32(kick))
        XCTAssertEqual(ab_core_track_count(core), 1)
    }

    func testEmptyEngineIsSilent() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        ab_core_set_playing(core, 1)
        let m = renderMetrics(core, seconds: 0.2)
        XCTAssertEqual(m.peak, 0, accuracy: 1e-6, "no tracks -> silence")
    }

    func testStoppedIsSilent() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        let k = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        setStep(core, k, 0, 0, 120)
        let m = renderMetrics(core, seconds: 0.2)
        XCTAssertEqual(m.peak, 0, accuracy: 1e-6)
        XCTAssertEqual(ab_core_current_step(core), -1)
    }

    func testMultiTrackPatternIsFiniteAndAudible() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        ab_core_set_tempo(core, 120)
        let kick = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        let hat = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_HAT)
        let bass = addTrack(core, kind: AB_KIND_SYNTH, sound: AB_SYNTH_BASS)
        let lead = addTrack(core, kind: AB_KIND_SYNTH, sound: AB_SYNTH_LEAD)
        for s in stride(from: 0, to: 16, by: 4) { setStep(core, kick, s, 0, 120) }
        for s in 0..<16 { setStep(core, hat, s, 0, 70) }
        for s in [0, 8] { setStep(core, bass, s, 36, 110) }
        for s in [0, 3, 6, 10] { setStep(core, lead, s, 63, 100) }
        ab_core_set_playing(core, 1)

        let m = renderMetrics(core, seconds: 2.0)
        XCTAssertTrue(m.finite)
        XCTAssertGreaterThan(m.peak, 0.05)
        XCTAssertLessThanOrEqual(m.peak, 1.0)
        XCTAssertGreaterThan(m.rms, 0.001)
    }

    func testSoloGatesNonSoloedTracks() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        let beat = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        let silent = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_HAT)
        for s in 0..<16 { setStep(core, beat, s, 0, 120) }   // only `beat` has content
        ab_core_set_playing(core, 1)

        ab_core_set_track_solo(core, Int32(silent), 1)       // solo the EMPTY track
        let gated = renderMetrics(core, seconds: 0.5)
        XCTAssertEqual(gated.peak, 0, accuracy: 1e-6, "non-soloed tracks must be gated out")

        ab_core_set_track_solo(core, Int32(silent), 0)       // unsolo -> beat returns
        let open = renderMetrics(core, seconds: 0.5)
        XCTAssertGreaterThan(open.peak, 0.05, "clearing solo restores the mix")
    }

    func testMuteSilencesATrack() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        let k = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        for s in 0..<16 { setStep(core, k, s, 0, 120) }
        ab_core_set_track_mute(core, Int32(k), 1)
        ab_core_set_playing(core, 1)
        let m = renderMetrics(core, seconds: 0.5)
        XCTAssertEqual(m.peak, 0, accuracy: 1e-6, "muted lone track -> silence")
    }

    func testSongAdvancesPatterns() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        ab_core_set_tempo(core, 120) // 16 steps == 2.0s
        let k = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        setStep(core, k, 0, 0, 120, pattern: 0)
        setStep(core, k, 0, 0, 120, pattern: 1)
        var seq: [Int32] = [0, 1]
        ab_core_set_song(core, &seq, 2)
        ab_core_set_song_mode(core, 1)
        ab_core_set_playing(core, 1)

        _ = renderMetrics(core, seconds: 0.05)
        XCTAssertEqual(ab_core_current_pattern(core), 0, "song starts on the first section (pattern 0)")
        XCTAssertEqual(ab_core_song_position(core), 0, "song position starts at 0")
        _ = renderMetrics(core, seconds: 2.05) // cross one loop boundary
        XCTAssertEqual(ab_core_current_pattern(core), 1, "after one loop the song advances to pattern 1")
        XCTAssertEqual(ab_core_song_position(core), 1, "song position advances to the second section")
    }

    func testSongPositionDistinguishesRepeatedPatterns() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        ab_core_set_tempo(core, 120)
        _ = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        var seq: [Int32] = [0, 0, 0]   // three "A" sections
        ab_core_set_song(core, &seq, 3)
        ab_core_set_song_mode(core, 1)
        ab_core_set_playing(core, 1)
        _ = renderMetrics(core, seconds: 0.05)
        XCTAssertEqual(ab_core_song_position(core), 0)
        _ = renderMetrics(core, seconds: 2.05)
        XCTAssertEqual(ab_core_song_position(core), 1, "distinct position even though the pattern is the same")
    }

    // MARK: - Engine v2 (S1)

    /// Staged patches apply at the next control tick; in the app the engine renders
    /// continuously, so emulate that with a short settle render.
    private func settle(_ core: OpaquePointer?) {
        var l = [Float](repeating: 0, count: 256), r = [Float](repeating: 0, count: 256)
        ab_core_render(core, &l, &r, 256)
    }

    private func corrLR(_ core: OpaquePointer?, seconds: Double) -> Double {
        let total = Int(seconds * sr)
        var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
        var Ls = [Double](), Rs = [Double]()
        var done = 0
        while done < total {
            let frames = min(block, total - done)
            ab_core_render(core, &l, &r, Int32(frames))
            for i in 0..<frames { Ls.append(Double(l[i])); Rs.append(Double(r[i])) }
            done += frames
        }
        let n = Double(Ls.count)
        let mL = Ls.reduce(0, +) / n, mR = Rs.reduce(0, +) / n
        var cov = 0.0, vL = 0.0, vR = 0.0
        for i in 0..<Ls.count {
            cov += (Ls[i] - mL) * (Rs[i] - mR)
            vL += (Ls[i] - mL) * (Ls[i] - mL)
            vR += (Rs[i] - mR) * (Rs[i] - mR)
        }
        guard vL > 0, vR > 0 else { return 1.0 }
        return cov / (vL * vR).squareRoot()
    }

    func testPatchUnisonWidthDecorrelatesChannels() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        let t = addTrack(core, kind: AB_KIND_SYNTH, sound: AB_SYNTH_PLUCK)

        var wide = ABPatch(); ab_patch_init(&wide)
        wide.unison = 7; wide.unisonDetune = 25; wide.unisonWidth = 1.0
        wide.ampS = 1.0; wide.ampD = 0.01 // sustain so the tone holds
        wide.delaySend = 0; wide.reverbSend = 0 // FX decorrelate by design; measure the voice
        ab_core_set_patch(core, Int32(t), &wide)
        settle(core)
        ab_core_note_on(core, Int32(t), 60, 1.0)
        let cWide = corrLR(core, seconds: 0.3)
        XCTAssertLessThan(cWide, 0.9, "7-voice unison at full width must decorrelate L/R")

        var mono = ABPatch(); ab_patch_init(&mono)
        mono.unison = 1; mono.unisonWidth = 0; mono.ampS = 1.0; mono.ampD = 0.01
        mono.delaySend = 0; mono.reverbSend = 0
        ab_core_set_patch(core, Int32(t), &mono)
        settle(core)   // also lets the wide note's tail fade under the new config
        _ = renderMetrics(core, seconds: 0.5)
        ab_core_note_on(core, Int32(t), 60, 1.0)
        let cMono = corrLR(core, seconds: 0.3)
        XCTAssertGreaterThan(cMono, 0.98, "single voice, no width -> effectively mono")
    }

    func testPatchCutoffChangesBrightness() {
        // High-frequency energy proxy: RMS of the first difference of the signal.
        func hfEnergy(_ cutoff: Float) -> Double {
            let core = ab_core_create(sr); defer { ab_core_destroy(core) }
            let t = addTrack(core, kind: AB_KIND_SYNTH, sound: AB_SYNTH_PLUCK)
            var p = ABPatch(); ab_patch_init(&p)
            p.cutoff = cutoff; p.envAmount = 0; p.lfoTarget = Int32(AB_LFO_OFF)
            p.ampS = 1.0; p.ampD = 0.01; p.unison = 1; p.unisonWidth = 0
            ab_core_set_patch(core, Int32(t), &p)
            settle(core)
            ab_core_note_on(core, Int32(t), 48, 1.0)
            let total = Int(0.3 * sr)
            var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
            var prev: Float = 0, sum = 0.0, n = 0, done = 0
            while done < total {
                let frames = min(block, total - done)
                ab_core_render(core, &l, &r, Int32(frames))
                for i in 0..<frames {
                    let d = Double(l[i] - prev); prev = l[i]
                    sum += d * d; n += 1
                }
                done += frames
            }
            return (sum / Double(n)).squareRoot()
        }
        let dark = hfEnergy(200), bright = hfEnergy(9000)
        XCTAssertGreaterThan(bright, dark * 2.0, "opening the filter must add high-frequency energy")
    }

    func testExtremeNoteInputIsClampedAndEngineSurvives() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        let t = addTrack(core, kind: AB_KIND_SYNTH, sound: AB_SYNTH_LEAD)
        setStep(core, t, 0, 30_000, 127)   // hostile note value
        ab_core_set_playing(core, 1)
        let m1 = renderMetrics(core, seconds: 2.0)
        XCTAssertTrue(m1.finite, "clamped input must not produce NaN/Inf")
        XCTAssertLessThanOrEqual(m1.peak, 1.0)
        // Engine must still be alive and audible afterwards.
        ab_core_note_on(core, Int32(t), 60, 1.0)
        let m2 = renderMetrics(core, seconds: 0.5)
        XCTAssertTrue(m2.finite)
        XCTAssertGreaterThan(m2.peak, 0.01, "audio path must survive hostile input")
    }

    func testClearingSongWhileSongPlayingDoesNotCrash() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        ab_core_set_tempo(core, 240)   // fast loops -> many boundaries
        let k = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        setStep(core, k, 0, 0, 120)
        var seq: [Int32] = [0]
        ab_core_set_song(core, &seq, 1)
        ab_core_set_song_mode(core, 1)
        ab_core_set_playing(core, 1)
        _ = renderMetrics(core, seconds: 0.5)
        ab_core_set_song(core, nil, 0)         // empty the song mid-play (audit: %0)
        let m = renderMetrics(core, seconds: 2.5) // crosses several loop boundaries
        XCTAssertTrue(m.finite, "emptying the song mid-play must not crash or corrupt")
    }

    func testSequencerAdvancesAtTempo() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        ab_core_set_tempo(core, 120)
        _ = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        ab_core_set_playing(core, 1)
        var sl = [Float](repeating: 0, count: 256), sr2 = [Float](repeating: 0, count: 256)
        ab_core_render(core, &sl, &sr2, 256)
        XCTAssertEqual(ab_core_current_step(core), 0)
        var rendered = 256
        let target = Int(0.13 * sr)
        while rendered < target { ab_core_render(core, &sl, &sr2, 256); rendered += 256 }
        XCTAssertEqual(ab_core_current_step(core), 1)
    }
}
