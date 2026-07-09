//
//  ScaleTests.swift
//  Theory tests: scale-locking guarantees every editor row is in key.
//

import XCTest

final class ScaleTests: XCTestCase {

    func testMajorIntervals() {
        XCTAssertEqual(Scale.major.intervals, [0, 2, 4, 5, 7, 9, 11])
        XCTAssertEqual(Scale.minorPentatonic.degreeCount, 5)
    }

    func testRowZeroIsRootAndOctaveWraps() {
        let ctx = MusicalContext(root: 0, scale: .major, baseOctave: 4) // C major, C4 = 60
        XCTAssertEqual(ctx.midiNote(forRow: 0), 60)
        XCTAssertEqual(ctx.midiNote(forRow: 7), 72)  // one octave up = root again
        XCTAssertEqual(ctx.midiNote(forRow: 1), 62)  // D4
        XCTAssertEqual(ctx.midiNote(forRow: -7), 48) // one octave down
    }

    func testEveryRowIsInScale() {
        let ctx = MusicalContext(root: 3, scale: .dorian, baseOctave: 3) // Eb dorian
        for row in -14...28 {
            XCTAssertTrue(ctx.contains(midi: ctx.midiNote(forRow: row)),
                          "row \(row) -> \(ctx.midiNote(forRow: row)) must be in scale")
        }
    }

    func testContainsRespectsKey() {
        let cMinor = MusicalContext(root: 0, scale: .naturalMinor, baseOctave: 3)
        XCTAssertTrue(cMinor.contains(midi: 63))  // Eb
        XCTAssertFalse(cMinor.contains(midi: 64)) // E natural is not in C minor
    }

    func testSnapPullsToNearestInScaleNote() {
        let cMinor = MusicalContext(root: 0, scale: .naturalMinor, baseOctave: 3)
        let snapped = cMinor.snap(midi: 64) // E4 -> nearest in-scale
        XCTAssertTrue(cMinor.contains(midi: snapped))
        XCTAssertLessThanOrEqual(abs(snapped - 64), 1)
        XCTAssertEqual(cMinor.snap(midi: 63), 63) // already in scale -> unchanged
    }

    func testChangingRootTransposes() {
        let c = MusicalContext(root: 0, scale: .major, baseOctave: 4)
        let d = MusicalContext(root: 2, scale: .major, baseOctave: 4)
        XCTAssertEqual(d.midiNote(forRow: 0) - c.midiNote(forRow: 0), 2)
        XCTAssertEqual(d.midiNote(forRow: 4) - c.midiNote(forRow: 4), 2)
    }

    func testNoteNames() {
        let ctx = MusicalContext(root: 0, scale: .major, baseOctave: 4)
        XCTAssertEqual(ctx.noteName(forRow: 0), "C4")
        XCTAssertEqual(ctx.noteName(forRow: 7), "C5")
    }
}

final class TheoryCoachTests: XCTestCase {
    let ctx = MusicalContext(root: 0, scale: .naturalMinor, baseOctave: 3)

    func testEmptyAndSingleNoteGiveNoReading() {
        XCTAssertNil(TheoryCoach.read(melody: Array(repeating: nil, count: 16), context: ctx))
        var one: [Int?] = Array(repeating: nil, count: 16); one[0] = 7
        XCTAssertNil(TheoryCoach.read(melody: one, context: ctx))
    }

    func testAnchoredMelodyIsCalledAnchored() {
        // Root/fifth on every strong beat (degrees 0 and 4 in natural minor).
        var lane: [Int?] = Array(repeating: nil, count: 16)
        lane[0] = 7; lane[4] = 11; lane[8] = 7; lane[12] = 11   // root, fifth (rows n=7: 7=root oct2, 11=deg4)
        lane[2] = 8; lane[6] = 9
        let r = TheoryCoach.read(melody: lane, context: ctx)
        XCTAssertNotNil(r)
        XCTAssertTrue(r!.headline.contains("anchored"), "got: \(r!.headline)")
    }

    func testStepwiseRisingLineIsDescribed() {
        var lane: [Int?] = Array(repeating: nil, count: 16)
        for s in 0..<8 { lane[s * 2] = s }   // 0,1,2,...,7 — pure rising steps
        let r = TheoryCoach.read(melody: lane, context: ctx)!
        XCTAssertTrue(r.headline.contains("rising"), "got: \(r.headline)")
        XCTAssertFalse(r.lesson.isEmpty)
    }
}
