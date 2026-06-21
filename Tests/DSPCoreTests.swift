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
    private func setStep(_ core: OpaquePointer?, _ track: Int, _ step: Int, _ note: Int, _ vel: Int) {
        ab_core_set_step(core, Int32(track), Int32(step), Int32(note), Int32(vel))
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

    func testMuteSilencesATrack() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        let k = addTrack(core, kind: AB_KIND_DRUM, sound: AB_DRUM_KICK)
        for s in 0..<16 { setStep(core, k, s, 0, 120) }
        ab_core_set_track_mute(core, Int32(k), 1)
        ab_core_set_playing(core, 1)
        let m = renderMetrics(core, seconds: 0.5)
        XCTAssertEqual(m.peak, 0, accuracy: 1e-6, "muted lone track -> silence")
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
