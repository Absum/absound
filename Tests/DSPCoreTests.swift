//
//  DSPCoreTests.swift
//  M0 smoke tests: prove the C++ DSP core is reachable and behaves.
//

import XCTest

final class DSPCoreTests: XCTestCase {

    func testVersionStringIsExposed() {
        let version = String(cString: ab_synth_version())
        XCTAssertFalse(version.isEmpty, "DSP core should report a version")
        XCTAssertTrue(version.contains("Absound"))
    }

    func testRenderIsSilentBeforeNoteOn() {
        let voice = ab_synth_create(44_100)
        defer { ab_synth_destroy(voice) }
        var buffer = [Float](repeating: 1.0, count: 256)
        ab_synth_render(voice, &buffer, buffer.count)
        XCTAssertTrue(buffer.allSatisfy { $0 == 0 }, "no note triggered -> silence")
    }

    func testNoteOnProducesSignal() {
        let voice = ab_synth_create(44_100)
        defer { ab_synth_destroy(voice) }
        ab_synth_note_on(voice, 69, 1.0) // A4
        var buffer = [Float](repeating: 0, count: 4_096)
        ab_synth_render(voice, &buffer, buffer.count)
        let peak = buffer.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.1, "a triggered note should produce audible signal")
    }
}
