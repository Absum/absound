//
//  SynthPatch.swift
//  Swift mirror of the engine's ABPatch plus identity (name/category), and the
//  factory preset library. A Layer embeds its SynthPatch value, so projects are
//  self-contained; the library is just a palette to copy from.
//

import Foundation

enum PatchCategory: String, Codable, CaseIterable, Identifiable {
    case bass = "Bass", lead = "Lead", pluck = "Pluck", pad = "Pad", keys = "Keys"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .bass: return "waveform.path"
        case .lead: return "bolt.fill"
        case .pluck: return "drop.fill"
        case .pad: return "cloud.fill"
        case .keys: return "pianokeys"
        }
    }
}

struct SynthPatch: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var category: PatchCategory
    var isFactory: Bool = true

    // Oscillators
    var osc1Wave: Int = 0        // AB_WAVE_*
    var osc2Wave: Int = 0
    var oscMix: Float = 0        // 0 = osc1 only
    var osc2Semi: Int = 0
    var osc2Fine: Float = 0
    var unison: Int = 1
    var unisonDetune: Float = 0  // cents
    var unisonWidth: Float = 0
    var subLevel: Float = 0.3
    var noiseLevel: Float = 0
    // Filter
    var filterType: Int = 0      // AB_FILTER_*
    var cutoff: Float = 900
    var resonance: Float = 0.35
    var drive: Float = 0.1
    var envAmount: Float = 0.55
    var keyTrack: Float = 0.4
    // Envelopes
    var ampA: Float = 0.003, ampD: Float = 0.25, ampS: Float = 0, ampR: Float = 0.15
    var modA: Float = 0.002, modD: Float = 0.18, modS: Float = 0.1, modR: Float = 0.12
    // LFO
    var lfoShape: Int = 0
    var lfoTarget: Int = 0       // AB_LFO_*
    var lfoRateHz: Float = 5
    var lfoSync: Int = 0
    var lfoDepth: Float = 0
    // Voice / out
    var glide: Float = 0
    var velAmount: Float = 0.5
    var gain: Float = 0.85
    var pan: Float = 0
    var delaySend: Float = 0.15
    var reverbSend: Float = 0.12
    // Insert FX chain. Optional so pre-FX saves decode (nil == empty chain).
    var fx: [FXSlot]? = nil

    var fxChain: [FXSlot] {
        get { fx ?? [] }
        set { fx = newValue.isEmpty ? nil : newValue }
    }

    /// Bridge to the engine struct.
    func toAB() -> ABPatch {
        var p = ABPatch()
        ab_patch_init(&p)
        p.osc1Wave = Int32(osc1Wave); p.osc2Wave = Int32(osc2Wave)
        p.oscMix = oscMix; p.osc2Semi = Int32(osc2Semi); p.osc2Fine = osc2Fine
        p.unison = Int32(unison); p.unisonDetune = unisonDetune; p.unisonWidth = unisonWidth
        p.subLevel = subLevel; p.noiseLevel = noiseLevel
        p.filterType = Int32(filterType); p.cutoff = cutoff; p.resonance = resonance
        p.drive = drive; p.envAmount = envAmount; p.keyTrack = keyTrack
        p.ampA = ampA; p.ampD = ampD; p.ampS = ampS; p.ampR = ampR
        p.modA = modA; p.modD = modD; p.modS = modS; p.modR = modR
        p.lfoShape = Int32(lfoShape); p.lfoTarget = Int32(lfoTarget)
        p.lfoRateHz = lfoRateHz; p.lfoSync = Int32(lfoSync); p.lfoDepth = lfoDepth
        p.glide = glide; p.velAmount = velAmount
        p.gain = gain; p.pan = pan; p.delaySend = delaySend; p.reverbSend = reverbSend
        return p
    }
}

// MARK: - Factory library

enum PatchFactory {
    static let presets: [SynthPatch] = bass + lead + pluck + pad + keys

    static func named(_ name: String) -> SynthPatch {
        presets.first { $0.name == name } ?? presets[0]
    }

    // ---- Bass ----
    private static let bass: [SynthPatch] = [
        {
            var p = SynthPatch(name: "Deep Sub", category: .bass)
            p.osc1Wave = 3; p.subLevel = 1.0; p.cutoff = 220; p.resonance = 0.2
            p.drive = 0.3; p.envAmount = 0.15; p.keyTrack = 0.1
            p.ampD = 0.25; p.ampS = 0.7; p.ampR = 0.08
            p.velAmount = 0.3; p.gain = 1.0; p.delaySend = 0; p.reverbSend = 0.02
            p.fx = [FXSlot(type: .comp, p1: 0.4, p2: 5, p3: 0.1, p4: 1.3)]
            return p
        }(),
        {
            var p = SynthPatch(name: "Acid Line", category: .bass)
            p.osc1Wave = 0; p.subLevel = 0.25; p.cutoff = 300; p.resonance = 0.85
            p.drive = 0.45; p.envAmount = 0.75; p.keyTrack = 0.3
            p.ampD = 0.18; p.ampS = 0.35; p.ampR = 0.08
            p.modD = 0.14; p.modS = 0.0
            p.glide = 0.06; p.velAmount = 0.7; p.gain = 0.85
            p.delaySend = 0.08; p.reverbSend = 0.04
            p.fx = [FXSlot(type: .drive, p1: 0.65, p2: 0, p3: 0.55, p4: 1.0), FXSlot(type: .comp, p1: 0.3, p2: 6, p3: 0.12, p4: 1.3)]
            return p
        }(),
        {
            var p = SynthPatch(name: "Growl", category: .bass)
            p.osc1Wave = 1; p.osc2Wave = 0; p.oscMix = 0.45; p.osc2Semi = -12
            p.subLevel = 0.6; p.cutoff = 380; p.resonance = 0.55; p.drive = 0.6
            p.envAmount = 0.4; p.lfoTarget = 2; p.lfoShape = 0; p.lfoSync = 8; p.lfoDepth = 0.35
            p.ampD = 0.3; p.ampS = 0.6; p.ampR = 0.1
            p.gain = 0.85; p.delaySend = 0.04; p.reverbSend = 0.05
            p.fx = [FXSlot(type: .wah, p1: 0.8, p2: 0.8, p3: 0.75, p4: 0.9), FXSlot(type: .drive, p1: 0.4, p2: 0, p3: 0.5, p4: 0.8)]
            return p
        }(),
    ]

    // ---- Lead ----
    private static let lead: [SynthPatch] = [
        {
            var p = SynthPatch(name: "Super Saw", category: .lead)
            p.osc1Wave = 0; p.unison = 7; p.unisonDetune = 22; p.unisonWidth = 0.9
            p.oscMix = 0.2; p.osc2Wave = 0; p.osc2Semi = -12; p.subLevel = 0.1
            p.cutoff = 1800; p.resonance = 0.25; p.envAmount = 0.45
            p.ampA = 0.006; p.ampD = 0.3; p.ampS = 0.7; p.ampR = 0.25
            p.lfoTarget = 1; p.lfoRateHz = 5.2; p.lfoDepth = 0.10
            p.delaySend = 0.3; p.reverbSend = 0.22
            p.fx = [FXSlot(type: .chorus, p1: 0.5, p2: 0.7, p3: 0.45, p4: 0.15), FXSlot(type: .width, p1: 1.5, p2: 140, p3: 0, p4: 0)]
            return p
        }(),
        {
            var p = SynthPatch(name: "Laser", category: .lead)
            p.osc1Wave = 1; p.unison = 3; p.unisonDetune = 10; p.unisonWidth = 0.5
            p.subLevel = 0; p.noiseLevel = 0.05
            p.cutoff = 2600; p.resonance = 0.5; p.envAmount = 0.65
            p.ampA = 0.002; p.ampD = 0.12; p.ampS = 0.45; p.ampR = 0.12
            p.lfoTarget = 1; p.lfoRateHz = 6.5; p.lfoDepth = 0.22
            p.glide = 0.05; p.delaySend = 0.35; p.reverbSend = 0.15
            p.fx = [FXSlot(type: .delay, p1: 8, p2: 0.55, p3: 0.55, p4: 0.4)]
            return p
        }(),
        {
            var p = SynthPatch(name: "Retro Square", category: .lead)
            p.osc1Wave = 1; p.unison = 2; p.unisonDetune = 8; p.unisonWidth = 0.4
            p.subLevel = 0.2; p.cutoff = 1500; p.resonance = 0.3; p.envAmount = 0.35
            p.ampA = 0.004; p.ampD = 0.2; p.ampS = 0.6; p.ampR = 0.15
            p.lfoTarget = 1; p.lfoRateHz = 4.8; p.lfoDepth = 0.08
            p.delaySend = 0.22; p.reverbSend = 0.12
            return p
        }(),
        {
            var p = SynthPatch(name: "Sky Saw", category: .lead)
            p.osc1Wave = 0; p.unison = 5; p.unisonDetune = 14; p.unisonWidth = 0.7
            p.subLevel = 0.15; p.cutoff = 3200; p.resonance = 0.2; p.envAmount = 0.3
            p.ampA = 0.01; p.ampD = 0.25; p.ampS = 0.75; p.ampR = 0.3
            p.delaySend = 0.25; p.reverbSend = 0.3
            return p
        }(),
    ]

    // ---- Pluck ----
    private static let pluck: [SynthPatch] = [
        {
            var p = SynthPatch(name: "Ice Pluck", category: .pluck)
            p.osc1Wave = 0; p.unison = 3; p.unisonDetune = 9; p.unisonWidth = 0.6
            p.subLevel = 0.25; p.cutoff = 750; p.resonance = 0.45; p.drive = 0.15
            p.envAmount = 0.8; p.ampA = 0.002; p.ampD = 0.16; p.ampS = 0; p.ampR = 0.12
            p.modD = 0.11; p.modS = 0
            p.velAmount = 0.7; p.delaySend = 0.3; p.reverbSend = 0.2
            p.fx = [FXSlot(type: .room, p1: 0.7, p2: 0.3, p3: 0.35, p4: 12)]
            return p
        }(),
        {
            var p = SynthPatch(name: "Frost Mallet", category: .pluck)
            p.osc1Wave = 2; p.osc2Wave = 3; p.oscMix = 0.4; p.osc2Semi = 12
            p.unison = 1; p.subLevel = 0.15; p.noiseLevel = 0.04
            p.cutoff = 2200; p.resonance = 0.2; p.envAmount = 0.5
            p.ampA = 0.001; p.ampD = 0.22; p.ampS = 0; p.ampR = 0.18
            p.modD = 0.08; p.modS = 0
            p.velAmount = 0.8; p.delaySend = 0.25; p.reverbSend = 0.3
            return p
        }(),
        {
            var p = SynthPatch(name: "Neon Arp", category: .pluck)
            p.osc1Wave = 1; p.unison = 2; p.unisonDetune = 6; p.unisonWidth = 0.5
            p.subLevel = 0.2; p.cutoff = 900; p.resonance = 0.6; p.drive = 0.2
            p.envAmount = 0.7; p.ampA = 0.001; p.ampD = 0.1; p.ampS = 0; p.ampR = 0.08
            p.modD = 0.07; p.modS = 0
            p.velAmount = 0.6; p.delaySend = 0.4; p.reverbSend = 0.12
            p.fx = [FXSlot(type: .crush, p1: 10, p2: 3, p3: 0.5, p4: 0), FXSlot(type: .delay, p1: 16, p2: 0.5, p3: 0.6, p4: 0.35)]
            return p
        }(),
    ]

    // ---- Pad ----
    private static let pad: [SynthPatch] = [
        {
            var p = SynthPatch(name: "Aurora Pad", category: .pad)
            p.osc1Wave = 0; p.unison = 7; p.unisonDetune = 16; p.unisonWidth = 1.0
            p.oscMix = 0.25; p.osc2Wave = 0; p.osc2Semi = 12; p.subLevel = 0.2
            p.cutoff = 1100; p.resonance = 0.2; p.envAmount = 0.25
            p.ampA = 0.6; p.ampD = 0.5; p.ampS = 0.8; p.ampR = 0.9
            p.modA = 0.8; p.modS = 0.5
            p.lfoTarget = 2; p.lfoSync = 1; p.lfoDepth = 0.2
            p.velAmount = 0.2; p.gain = 0.7; p.delaySend = 0.15; p.reverbSend = 0.45
            return p
        }(),
        {
            var p = SynthPatch(name: "Glacier Strings", category: .pad)
            p.osc1Wave = 0; p.unison = 5; p.unisonDetune = 12; p.unisonWidth = 0.8
            p.subLevel = 0.1; p.noiseLevel = 0.03
            p.cutoff = 2000; p.resonance = 0.15; p.envAmount = 0.15
            p.ampA = 0.35; p.ampD = 0.4; p.ampS = 0.85; p.ampR = 0.7
            p.lfoTarget = 1; p.lfoRateHz = 4.5; p.lfoDepth = 0.06
            p.velAmount = 0.25; p.gain = 0.7; p.delaySend = 0.1; p.reverbSend = 0.4
            return p
        }(),
        {
            var p = SynthPatch(name: "Night Drone", category: .pad)
            p.osc1Wave = 1; p.osc2Wave = 0; p.oscMix = 0.5; p.osc2Semi = -12
            p.unison = 3; p.unisonDetune = 10; p.unisonWidth = 0.7; p.subLevel = 0.4
            p.filterType = 1; p.cutoff = 600; p.resonance = 0.4; p.envAmount = 0.1
            p.ampA = 0.9; p.ampD = 0.5; p.ampS = 0.9; p.ampR = 1.2
            p.lfoTarget = 4; p.lfoSync = 2; p.lfoDepth = 0.5
            p.velAmount = 0.1; p.gain = 0.65; p.delaySend = 0.2; p.reverbSend = 0.5
            p.fx = [FXSlot(type: .phaser, p1: 0.25, p2: 0.9, p3: 0.5, p4: 0.8), FXSlot(type: .gate, p1: 16, p2: 5, p3: 0.85, p4: 8)]
            return p
        }(),
    ]

    // ---- Keys ----
    private static let keys: [SynthPatch] = [
        {
            var p = SynthPatch(name: "Glass Keys", category: .keys)
            p.osc1Wave = 2; p.osc2Wave = 3; p.oscMix = 0.35
            p.unison = 2; p.unisonDetune = 5; p.unisonWidth = 0.5
            p.subLevel = 0.2; p.cutoff = 2600; p.resonance = 0.2; p.envAmount = 0.3
            p.ampA = 0.002; p.ampD = 0.4; p.ampS = 0.35; p.ampR = 0.35
            p.velAmount = 0.75; p.delaySend = 0.12; p.reverbSend = 0.28
            return p
        }(),
        {
            var p = SynthPatch(name: "Soft EP", category: .keys)
            p.osc1Wave = 3; p.osc2Wave = 2; p.oscMix = 0.3; p.osc2Semi = 12
            p.unison = 1; p.subLevel = 0.3; p.cutoff = 1600; p.resonance = 0.15
            p.envAmount = 0.35; p.ampA = 0.003; p.ampD = 0.5; p.ampS = 0.45; p.ampR = 0.4
            p.lfoTarget = 3; p.lfoRateHz = 5.5; p.lfoDepth = 0.15
            p.velAmount = 0.85; p.delaySend = 0.08; p.reverbSend = 0.22
            p.fx = [FXSlot(type: .tremPan, p1: 8, p2: 0.5, p3: 0.2, p4: 1), FXSlot(type: .room, p1: 0.45, p2: 0.5, p3: 0.25, p4: 8)]
            return p
        }(),
        {
            var p = SynthPatch(name: "Dream Bells", category: .keys)
            p.osc1Wave = 3; p.osc2Wave = 3; p.oscMix = 0.45; p.osc2Semi = 19
            p.unison = 1; p.subLevel = 0.1; p.cutoff = 4000; p.resonance = 0.1
            p.envAmount = 0.2; p.ampA = 0.002; p.ampD = 0.9; p.ampS = 0; p.ampR = 0.8
            p.modD = 0.4; p.modS = 0
            p.velAmount = 0.7; p.delaySend = 0.3; p.reverbSend = 0.4
            return p
        }(),
    ]
}
