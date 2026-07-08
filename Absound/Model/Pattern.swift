//
//  Pattern.swift
//  Project model: global instrument Layers + multiple Patterns (per-layer step
//  content) + a Song (sequence of pattern indices).
//
//  Layers are shared across patterns — a pattern only changes what each layer
//  plays. Melody is stored as scale-degree rows so key/scale changes re-voice.
//  Codable so M-later can persist projects.
//

import Foundation

enum TrackKind: Int, Codable { case synth = 0, drum = 1 }

/// Drum voices — rawValue matches the engine's AB_DRUM_* enum.
enum DrumSound: Int, CaseIterable, Identifiable, Codable {
    case kick = 0, snare, hat, openHat, clap, tom, rim, perc
    var id: Int { rawValue }
    var name: String { ["Kick", "Snare", "Hat", "Open Hat", "Clap", "Tom", "Rim", "Perc"][rawValue] }
}

/// A global instrument (one engine track). Shared by every pattern.
/// Synth layers embed their full SynthPatch (self-contained projects);
/// drum layers keep the parametric DrumSound enum.
struct Layer: Identifiable, Codable {
    var id = UUID()
    var engineId: Int = -1       // runtime engine slot — NOT persisted (re-registered on load)
    var kind: TrackKind
    var sound: Int               // DrumSound raw value (drum layers only)
    var patch: SynthPatch?       // synth layers only
    var muted: Bool = false

    // engineId is a live handle; persisting it would route edits to wrong slots after a reload.
    enum CodingKeys: String, CodingKey { case id, kind, sound, patch, muted }

    static func synth(_ patch: SynthPatch) -> Layer { Layer(kind: .synth, sound: 0, patch: patch) }
    static func drum(_ sound: DrumSound) -> Layer { Layer(kind: .drum, sound: sound.rawValue) }

    var displayName: String {
        kind == .synth ? (patch?.name ?? "Synth")
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

/// One 16-step pattern: per-layer content keyed by layer id.
struct PatternData: Identifiable, Codable {
    var id = UUID()
    var name: String
    var melodies: [UUID: [Int?]] = [:]   // synth layer id -> rows
    var drums: [UUID: [Bool]] = [:]      // drum layer id -> on/off

    func melody(_ layer: UUID) -> [Int?] { melodies[layer] ?? Array(repeating: nil, count: Project.stepCount) }
    func drumLane(_ layer: UUID) -> [Bool] { drums[layer] ?? Array(repeating: false, count: Project.stepCount) }
}

struct Project: Codable {
    static let stepCount = Int(AB_NUM_STEPS)
    static let maxPatterns = Int(AB_MAX_PATTERNS)
    static let patternNames = ["A", "B", "C", "D", "E", "F", "G", "H"]

    var contextRoot: Int
    var scaleRaw: String
    var baseOctave: Int
    var tempo: Double = 112
    var layers: [Layer]
    var patterns: [PatternData]
    var song: [Int]                  // indices into `patterns`
    var currentPatternIndex: Int     // which pattern the Studio edits

    var context: MusicalContext {
        MusicalContext(root: contextRoot,
                       scale: Scale(rawValue: scaleRaw) ?? .naturalMinor,
                       baseOctave: baseOctave)
    }

    static func demo() -> Project {
        let kick = Layer.drum(.kick), snare = Layer.drum(.snare), hat = Layer.drum(.hat)
        let bass = Layer.synth(PatchFactory.named("Deep Sub"))
        let lead = Layer.synth(PatchFactory.named("Super Saw"))
        let layers = [kick, snare, hat, bass, lead]

        var a = PatternData(name: "A")
        a.drums[kick.id] = boolLane([0, 4, 8, 11])
        a.drums[snare.id] = boolLane([4, 12])
        a.drums[hat.id] = boolLane(Array(0..<stepCount))
        a.melodies[bass.id] = rowLane([(0, 0), (8, 0), (11, 2)])
        a.melodies[lead.id] = rowLane([(0, 7), (3, 9), (6, 11), (8, 13), (10, 11), (13, 9), (14, 10)])

        return Project(contextRoot: 0, scaleRaw: Scale.naturalMinor.rawValue, baseOctave: 3,
                       layers: layers, patterns: [a], song: [0], currentPatternIndex: 0)
    }

    private static func boolLane(_ on: [Int]) -> [Bool] {
        var l = Array(repeating: false, count: stepCount); for s in on { l[s] = true }; return l
    }
    private static func rowLane(_ notes: [(Int, Int)]) -> [Int?] {
        var l = [Int?](repeating: nil, count: stepCount); for (s, r) in notes { l[s] = r }; return l
    }
}
