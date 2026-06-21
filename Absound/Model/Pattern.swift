//
//  Pattern.swift
//  A single 16-step pattern: three drum lanes plus a monophonic melody lane.
//
//  The melody stores a scale *row* per step (not an absolute pitch), so changing
//  key/scale re-voices the riff while keeping its contour. Drum lanes are on/off.
//  Codable so M4 can persist and arrange patterns into songs.
//

import Foundation

/// Synth timbres exposed by the C++ core (ab_core_set_synth_preset).
enum SynthPreset: Int, CaseIterable, Identifiable {
    case pluck = 0, bass, lead, keys
    var id: Int { rawValue }
    var name: String {
        switch self {
        case .pluck: return "Pluck"
        case .bass: return "Bass"
        case .lead: return "Lead"
        case .keys: return "Keys"
        }
    }
}

/// Drum lanes, in the engine's track order.
enum DrumLane: Int, CaseIterable, Identifiable {
    case kick, snare, hat
    var id: Int { rawValue }
    var label: String { ["Kick", "Snare", "Hat"][rawValue] }
    /// Engine track id (AB_TRACK_KICK == 1, SNARE == 2, HAT == 3).
    var engineTrack: Int32 { Int32(rawValue) + Int32(AB_TRACK_KICK) }
    var velocity: Int { [120, 112, 92][rawValue] }
}

struct Pattern: Codable, Equatable {
    static let stepCount = Int(AB_NUM_STEPS)

    var contextRoot: Int
    var scaleRaw: String
    var baseOctave: Int

    /// Drum hits — [lane][step].
    var drums: [[Bool]]
    /// Melody row per step (nil = rest).
    var melody: [Int?]
    var presetRaw: Int

    var context: MusicalContext {
        MusicalContext(root: contextRoot,
                       scale: Scale(rawValue: scaleRaw) ?? .naturalMinor,
                       baseOctave: baseOctave)
    }

    init(context: MusicalContext = MusicalContext(), preset: SynthPreset = .pluck) {
        contextRoot = context.root
        scaleRaw = context.scale.rawValue
        baseOctave = context.baseOctave
        drums = Array(repeating: Array(repeating: false, count: Pattern.stepCount), count: DrumLane.allCases.count)
        melody = Array(repeating: nil, count: Pattern.stepCount)
        presetRaw = preset.rawValue
    }

    var melodyVelocity: Int { 105 }

    /// A starter groove in the current key so the Studio isn't empty on first launch.
    static func demo() -> Pattern {
        var p = Pattern(context: MusicalContext(root: 0, scale: .naturalMinor, baseOctave: 3), preset: .pluck)
        for s in [0, 4, 8, 11] { p.drums[DrumLane.kick.rawValue][s] = true }
        for s in [4, 12] { p.drums[DrumLane.snare.rawValue][s] = true }
        for s in 0..<stepCount { p.drums[DrumLane.hat.rawValue][s] = true }
        // C-minor riff as scale rows (baseOctave 3): row7=C4, 9=Eb4, 10=F4, 11=G4, 13=Bb4.
        let riff: [(Int, Int)] = [(0, 7), (3, 9), (6, 11), (8, 13), (10, 11), (13, 9), (14, 10)]
        for (step, row) in riff { p.melody[step] = row }
        return p
    }
}
