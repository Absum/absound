//
//  Scale.swift
//  Music-theory core: scales, the current key/scale context, and scale-locking.
//
//  The melody editor maps grid *rows* to in-scale pitches via MusicalContext, so
//  every cell a user can tap is guaranteed to be in key — the "make melodies
//  easily" magic. snap(midi:) handles arbitrary input (live/Highway) later.
//
//  Pure Swift, no UIKit — unit-tested in Tests/.
//

import Foundation

enum Scale: String, CaseIterable, Identifiable {
    case major
    case naturalMinor
    case harmonicMinor
    case dorian
    case phrygian
    case mixolydian
    case lydian
    case majorPentatonic
    case minorPentatonic
    case blues

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .major: return "Major"
        case .naturalMinor: return "Minor"
        case .harmonicMinor: return "Harmonic Minor"
        case .dorian: return "Dorian"
        case .phrygian: return "Phrygian"
        case .mixolydian: return "Mixolydian"
        case .lydian: return "Lydian"
        case .majorPentatonic: return "Major Pentatonic"
        case .minorPentatonic: return "Minor Pentatonic"
        case .blues: return "Blues"
        }
    }

    /// Semitone offsets from the root within one octave (ascending, starting at 0).
    var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: return [0, 2, 3, 5, 7, 8, 11]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: return [0, 1, 3, 5, 7, 8, 10]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        case .lydian: return [0, 2, 4, 6, 7, 9, 11]
        case .majorPentatonic: return [0, 2, 4, 7, 9]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        case .blues: return [0, 3, 5, 6, 7, 10]
        }
    }

    var degreeCount: Int { intervals.count }
}

/// The active musical key/scale and the octave the editor is anchored to.
struct MusicalContext: Equatable {
    var root: Int          // pitch class 0..11 (C = 0)
    var scale: Scale
    var baseOctave: Int    // MIDI octave of the lowest editor row (C4 == 60)

    static let rootNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    init(root: Int = 0, scale: Scale = .naturalMinor, baseOctave: Int = 3) {
        self.root = ((root % 12) + 12) % 12
        self.scale = scale
        self.baseOctave = baseOctave
    }

    var rootName: String { MusicalContext.rootNames[root] }
    var displayName: String { "\(rootName) \(scale.displayName)" }

    /// MIDI note of the editor's lowest row (root at baseOctave).
    var baseMidi: Int { (baseOctave + 1) * 12 + root }

    /// Map an editor row (0 = root at baseOctave, climbing by scale degree) to a MIDI note.
    func midiNote(forRow row: Int) -> Int {
        let n = scale.degreeCount
        let octave = Int((Double(row) / Double(n)).rounded(.down))
        let degree = row - octave * n          // floored modulo, always 0..<n
        return baseMidi + octave * 12 + scale.intervals[degree]
    }

    /// Note name for a row, e.g. "Eb4" — used for the piano-roll's pitch labels.
    func noteName(forRow row: Int) -> String {
        let midi = midiNote(forRow: row)
        let name = MusicalContext.rootNames[((midi % 12) + 12) % 12]
        let octave = midi / 12 - 1
        return "\(name)\(octave)"
    }

    /// True if a MIDI note belongs to this key/scale.
    func contains(midi: Int) -> Bool {
        let pc = (((midi - root) % 12) + 12) % 12
        return scale.intervals.contains(pc)
    }

    /// Snap an arbitrary MIDI note to the nearest in-scale note (ties round up).
    func snap(midi: Int) -> Int {
        if contains(midi: midi) { return midi }
        for delta in 1...6 {
            if contains(midi: midi - delta) && contains(midi: midi + delta) { return midi + delta }
            if contains(midi: midi + delta) { return midi + delta }
            if contains(midi: midi - delta) { return midi - delta }
        }
        return midi
    }
}
