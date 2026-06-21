//
//  DSPCoreTests.swift
//  M1 audio-engine tests: render the engine offline and assert it behaves —
//  signal present, finite (no NaN/Inf), within range, and the sequencer steps.
//

import XCTest

final class DSPCoreTests: XCTestCase {

    private let sr = 44_100.0
    private let block = 512

    /// Typed wrapper — the C `int` params import as Int32, the enum constants as Int.
    private func setStep(_ core: OpaquePointer?, _ track: Int, _ step: Int, _ note: Int, _ vel: Int) {
        ab_core_set_step(core, Int32(track), Int32(step), Int32(note), Int32(vel))
    }

    /// Renders `seconds` of audio in blocks; returns (peak, rms, allFinite).
    private func renderMetrics(_ core: OpaquePointer?, seconds: Double) -> (peak: Float, rms: Double, finite: Bool) {
        let total = Int(seconds * sr)
        var l = [Float](repeating: 0, count: block)
        var r = [Float](repeating: 0, count: block)
        var peak: Float = 0
        var sumSq = 0.0
        var n = 0
        var finite = true
        var done = 0
        while done < total {
            let frames = min(block, total - done)
            ab_core_render(core, &l, &r, Int32(frames))
            for i in 0..<frames {
                let s = l[i]
                if !s.isFinite { finite = false }
                peak = max(peak, abs(s))
                sumSq += Double(s) * Double(s)
                n += 1
            }
            done += frames
        }
        return (peak, (n > 0 ? (sumSq / Double(n)).squareRoot() : 0), finite)
    }

    func testVersionExposed() {
        let v = String(cString: ab_core_version())
        XCTAssertTrue(v.contains("Absound"))
    }

    func testStoppedEngineIsSilent() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        setStep(core, AB_TRACK_KICK, 0, 60, 120) // pattern present but not playing
        let m = renderMetrics(core, seconds: 0.2)
        XCTAssertEqual(m.peak, 0, accuracy: 1e-6, "no transport -> silence")
        XCTAssertEqual(ab_core_current_step(core), -1)
    }

    func testPlayingPatternProducesFiniteInRangeSignal() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        ab_core_set_tempo(core, 120)
        // A simple beat + a synth note.
        for s in stride(from: 0, to: 16, by: 4) { setStep(core, AB_TRACK_KICK, s, 0, 120) }
        setStep(core, AB_TRACK_SNARE, 4, 0, 110)
        setStep(core, AB_TRACK_SNARE, 12, 0, 110)
        for s in 0..<16 { setStep(core, AB_TRACK_HAT, s, 0, 70) }
        setStep(core, AB_TRACK_SYNTH, 0, 63, 100) // Eb4
        ab_core_set_playing(core, 1)

        let m = renderMetrics(core, seconds: 2.0)
        XCTAssertTrue(m.finite, "no NaN/Inf in output")
        XCTAssertGreaterThan(m.peak, 0.05, "playing pattern should be audible")
        XCTAssertLessThanOrEqual(m.peak, 1.0, "limiter keeps output in range")
        XCTAssertGreaterThan(m.rms, 0.001, "sustained energy present")
    }

    func testSequencerAdvancesAtTempo() {
        let core = ab_core_create(sr); defer { ab_core_destroy(core) }
        ab_core_set_tempo(core, 120) // 120bpm -> 16th = 0.125s; step len ~5512 samples
        ab_core_set_playing(core, 1)
        var scratchL = [Float](repeating: 0, count: 256)
        var scratchR = [Float](repeating: 0, count: 256)

        // Render ~0.13s (just over one step) and confirm the step advanced from 0 to 1.
        ab_core_render(core, &scratchL, &scratchR, 256) // primes step 0
        XCTAssertEqual(ab_core_current_step(core), 0)
        var rendered = 256
        let target = Int(0.13 * sr)
        while rendered < target {
            ab_core_render(core, &scratchL, &scratchR, 256)
            rendered += 256
        }
        XCTAssertEqual(ab_core_current_step(core), 1, "after ~0.13s at 120bpm the sequencer is on step 1")
    }
}
