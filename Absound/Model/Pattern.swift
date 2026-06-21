//
//  Pattern.swift
//  A multi-track pattern: an ordered list of layers, each either a melodic synth
//  (its own preset + melody lane) or a drum (one percussion sound + on/off lane).
//
//  Melody is stored as scale-degree rows so changing key/scale re-voices while
//  keeping contour. Codable so M4 can persist and arrange patterns into songs.
//

import Foundation

enum TrackKind: Int, Codable { case synth = 0, drum = 1 }

/// Synth timbres — rawValue matches the engine's AB_SYNTH_* enum.
enum SynthPreset: Int, CaseIterable, Identifiable, Codable {
    case pluck = 0, bass, lead, keys
    var id: Int { rawValue }
    var name: String { ["Pluck", "Bass", "Lead", "Keys"][rawValue] }
}

/// Drum voices — rawValue matches the engine's AB_DRUM_* enum.
enum DrumSound: Int, CaseIterable, Identifiable, Codable {
    case kick = 0, snare, hat, openHat, clap, tom, rim, perc
    var id: Int { rawValue }
    var name: String { ["Kick", "Snare", "Hat", "Open Hat", "Clap", "Tom", "Rim", "Perc"][rawValue] }
}

/// One layer. A synth layer uses `melody`; a drum layer uses `drumSteps`.
struct LayerTrack: Identifiable, Codable {
    var id = UUID()
    var engineId: Int = -1          // handle into the C++ track pool (runtime)
    var kind: TrackKind
    var sound: Int                  // SynthPreset.rawValue or DrumSound.rawValue
    var muted: Bool = false
    var melody: [Int?]
    var drumSteps: [Bool]

    static func synth(_ preset: SynthPreset) -> LayerTrack {
        LayerTrack(kind: .synth, sound: preset.rawValue,
                   melody: Array(repeating: nil, count: Pattern.stepCount),
                   drumSteps: Array(repeating: false, count: Pattern.stepCount))
    }
    static func drum(_ sound: DrumSound) -> LayerTrack {
        LayerTrack(kind: .drum, sound: sound.rawValue,
                   melody: Array(repeating: nil, count: Pattern.stepCount),
                   drumSteps: Array(repeating: false, count: Pattern.stepCount))
    }

    var displayName: String {
        kind == .synth ? (SynthPreset(rawValue: sound)?.name ?? "Synth")
                       : (DrumSound(rawValue: sound)?.name ?? "Drum")
    }
    var melodyVelocity: Int { 105 }
    var drumVelocity: Int {
        switch DrumSound(rawValue: sound) ?? .kick {
        case .kick: return 122
        case .snare, .clap: return 112
        case .tom: return 110
        default: return 96
        }
    }
}

struct Pattern: Codable {
    static let stepCount = Int(AB_NUM_STEPS)

    var contextRoot: Int
    var scaleRaw: String
    var baseOctave: Int
    var tracks: [LayerTrack]

    var context: MusicalContext {
        MusicalContext(root: contextRoot,
                       scale: Scale(rawValue: scaleRaw) ?? .naturalMinor,
                       baseOctave: baseOctave)
    }

    init(context: MusicalContext = MusicalContext(), tracks: [LayerTrack] = []) {
        contextRoot = context.root
        scaleRaw = context.scale.rawValue
        baseOctave = context.baseOctave
        self.tracks = tracks
    }

    /// A starter arrangement: a beat plus a bass and a lead layer.
    static func demo() -> Pattern {
        var kick = LayerTrack.drum(.kick)
        for s in [0, 4, 8, 11] { kick.drumSteps[s] = true }
        var snare = LayerTrack.drum(.snare)
        for s in [4, 12] { snare.drumSteps[s] = true }
        var hat = LayerTrack.drum(.hat)
        for s in 0..<stepCount { hat.drumSteps[s] = true }

        var bass = LayerTrack.synth(.bass)
        for (s, r) in [(0, 0), (8, 0), (11, 2)] { bass.melody[s] = r }   // root/bass notes

        var lead = LayerTrack.synth(.lead)
        // C-minor riff as scale rows (baseOctave 3): row7=C4, 9=Eb4, 10=F4, 11=G4, 13=Bb4.
        for (s, r) in [(0, 7), (3, 9), (6, 11), (8, 13), (10, 11), (13, 9), (14, 10)] { lead.melody[s] = r }

        return Pattern(context: MusicalContext(root: 0, scale: .naturalMinor, baseOctave: 3),
                       tracks: [kick, snare, hat, bass, lead])
    }
}
