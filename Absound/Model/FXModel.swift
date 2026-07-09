//
//  FXModel.swift
//  Swift mirror of the engine's insert-FX chain: effect types with named,
//  ranged parameters (the engine sees generic p1..p4), Codable slots, and
//  bridging to ABFXChain.
//

import Foundation

enum FXType: Int, Codable, CaseIterable, Identifiable {
    case drive = 1, crush, chorus, phaser, eq, comp, tremPan, width, delay, ringMod, gate, wah, room

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .drive: return "Drive"
        case .crush: return "Bitcrush"
        case .chorus: return "Chorus"
        case .phaser: return "Phaser"
        case .eq: return "EQ"
        case .comp: return "Compressor"
        case .tremPan: return "Trem / Pan"
        case .width: return "Widener"
        case .delay: return "Delay"
        case .ringMod: return "Ring Mod"
        case .gate: return "Gate"
        case .wah: return "Auto-Wah"
        case .room: return "Room"
        }
    }
    var icon: String {
        switch self {
        case .drive: return "flame.fill"
        case .crush: return "square.grid.2x2"
        case .chorus: return "water.waves"
        case .phaser: return "tornado"
        case .eq: return "slider.horizontal.3"
        case .comp: return "rectangle.compress.vertical"
        case .tremPan: return "metronome"
        case .width: return "arrow.left.and.right"
        case .delay: return "wave.3.right"
        case .ringMod: return "circle.circle"
        case .gate: return "squareshape.split.3x3"
        case .wah: return "mouth"
        case .room: return "building.columns"
        }
    }

    struct Param {
        let label: String
        let range: ClosedRange<Float>
        let log: Bool
        let format: String
        let def: Float
    }

    /// Named parameter specs for p1..p4 (nil = unused).
    var params: [Param?] {
        switch self {
        case .drive: return [.init(label: "Amount", range: 0...1, log: false, format: "%.2f", def: 0.5),
                             .init(label: "Mode", range: 0...2, log: false, format: "%.0f", def: 0),
                             .init(label: "Tone", range: 0...1, log: false, format: "%.2f", def: 0.6),
                             .init(label: "Mix", range: 0...1, log: false, format: "%.2f", def: 1.0)]
        case .crush: return [.init(label: "Bits", range: 2...16, log: false, format: "%.0f", def: 8),
                             .init(label: "Downsmp", range: 1...40, log: false, format: "%.0f", def: 4),
                             .init(label: "Mix", range: 0...1, log: false, format: "%.2f", def: 1.0), nil]
        case .chorus: return [.init(label: "Rate", range: 0.05...5, log: true, format: "%.2fHz", def: 0.7),
                              .init(label: "Depth", range: 0...1, log: false, format: "%.2f", def: 0.6),
                              .init(label: "Mix", range: 0...1, log: false, format: "%.2f", def: 0.5),
                              .init(label: "Feedbk", range: 0...0.9, log: false, format: "%.2f", def: 0.1)]
        case .phaser: return [.init(label: "Rate", range: 0.05...5, log: true, format: "%.2fHz", def: 0.4),
                              .init(label: "Depth", range: 0...1, log: false, format: "%.2f", def: 0.8),
                              .init(label: "Feedbk", range: 0...0.7, log: false, format: "%.2f", def: 0.4),
                              .init(label: "Mix", range: 0...1, log: false, format: "%.2f", def: 0.7)]
        case .eq: return [.init(label: "Low", range: -12...12, log: false, format: "%.0fdB", def: 0),
                          .init(label: "Mid", range: -12...12, log: false, format: "%.0fdB", def: 0),
                          .init(label: "High", range: -12...12, log: false, format: "%.0fdB", def: 0),
                          .init(label: "MidHz", range: 200...5000, log: true, format: "%.0f", def: 1000)]
        case .comp: return [.init(label: "Thresh", range: 0.05...1, log: false, format: "%.2f", def: 0.35),
                            .init(label: "Ratio", range: 1...20, log: true, format: "%.0f:1", def: 4),
                            .init(label: "Release", range: 0.02...1, log: true, format: "%.2fs", def: 0.15),
                            .init(label: "Makeup", range: 0.5...2, log: false, format: "%.2f", def: 1.2)]
        case .tremPan: return [.init(label: "Rate", range: 1...32, log: false, format: "1/%.0f", def: 8),
                               .init(label: "Depth", range: 0...1, log: false, format: "%.2f", def: 0.8),
                               .init(label: "Shape", range: 0...1, log: false, format: "%.2f", def: 0.3),
                               .init(label: "Mode", range: 0...1, log: false, format: "%.0f", def: 0)]
        case .width: return [.init(label: "Width", range: 0...2, log: false, format: "%.2f", def: 1.4),
                             .init(label: "BassHz", range: 0...500, log: false, format: "%.0f", def: 120), nil, nil]
        case .delay: return [.init(label: "Time", range: 1...32, log: false, format: "1/%.0f", def: 8),
                             .init(label: "Feedbk", range: 0...0.85, log: false, format: "%.2f", def: 0.45),
                             .init(label: "Tone", range: 0...1, log: false, format: "%.2f", def: 0.6),
                             .init(label: "Mix", range: 0...1, log: false, format: "%.2f", def: 0.35)]
        case .ringMod: return [.init(label: "Freq", range: 20...4000, log: true, format: "%.0fHz", def: 300),
                               .init(label: "Mix", range: 0...1, log: false, format: "%.2f", def: 0.6),
                               .init(label: "Tone", range: 0...1, log: false, format: "%.2f", def: 0.8), nil]
        case .gate: return [.init(label: "Rate", range: 4...32, log: false, format: "1/%.0f", def: 16),
                            .init(label: "Pattern", range: 0...7, log: false, format: "%.0f", def: 0),
                            .init(label: "Depth", range: 0...1, log: false, format: "%.2f", def: 1.0),
                            .init(label: "Attack", range: 1...50, log: false, format: "%.0fms", def: 4)]
        case .wah: return [.init(label: "Sens", range: 0...1, log: false, format: "%.2f", def: 0.7),
                           .init(label: "Range", range: 0...1, log: false, format: "%.2f", def: 0.7),
                           .init(label: "Reso", range: 0...0.95, log: false, format: "%.2f", def: 0.7),
                           .init(label: "Mix", range: 0...1, log: false, format: "%.2f", def: 0.8)]
        case .room: return [.init(label: "Size", range: 0...1, log: false, format: "%.2f", def: 0.5),
                            .init(label: "Damp", range: 0...0.95, log: false, format: "%.2f", def: 0.4),
                            .init(label: "Mix", range: 0...1, log: false, format: "%.2f", def: 0.3),
                            .init(label: "PreDly", range: 0...50, log: false, format: "%.0fms", def: 5)]
        }
    }
}

struct FXSlot: Codable, Identifiable, Equatable {
    /// Tolerant decode: an unknown effect type (newer save, older app) becomes
    /// a disabled Drive slot instead of failing the whole chain.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let raw = try c.decode(Int.self, forKey: .type)
        if let t = FXType(rawValue: raw) {
            type = t
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        } else {
            print("⚠️ Absound: unknown FX type \(raw) in saved chain — slot disabled")
            type = .drive
            enabled = false
        }
        p1 = try c.decodeIfPresent(Float.self, forKey: .p1) ?? 0
        p2 = try c.decodeIfPresent(Float.self, forKey: .p2) ?? 0
        p3 = try c.decodeIfPresent(Float.self, forKey: .p3) ?? 0
        p4 = try c.decodeIfPresent(Float.self, forKey: .p4) ?? 0
    }

    var id = UUID()
    var type: FXType
    var enabled: Bool = true
    var p1: Float = 0, p2: Float = 0, p3: Float = 0, p4: Float = 0

    init(type: FXType) {
        self.type = type
        let d = type.params
        p1 = d.count > 0 ? (d[0]?.def ?? 0) : 0
        p2 = d.count > 1 ? (d[1]?.def ?? 0) : 0
        p3 = d.count > 2 ? (d[2]?.def ?? 0) : 0
        p4 = d.count > 3 ? (d[3]?.def ?? 0) : 0
    }

    init(type: FXType, p1: Float, p2: Float, p3: Float, p4: Float) {
        self.type = type
        self.p1 = p1; self.p2 = p2; self.p3 = p3; self.p4 = p4
    }

    subscript(param i: Int) -> Float {
        get { [p1, p2, p3, p4][i] }
        set {
            switch i {
            case 0: p1 = newValue
            case 1: p2 = newValue
            case 2: p3 = newValue
            default: p4 = newValue
            }
        }
    }
}

extension Array where Element == FXSlot {
    /// Bridge to the engine chain (first AB_MAX_FX slots).
    func toABChain() -> ABFXChain {
        var chain = ABFXChain()
        ab_fx_chain_init(&chain)
        let n = Swift.min(count, Int(AB_MAX_FX))
        withUnsafeMutablePointer(to: &chain.slots) { tuplePtr in
            tuplePtr.withMemoryRebound(to: ABFXSlot.self, capacity: Int(AB_MAX_FX)) { slots in
                for i in 0..<n {
                    slots[i].type = Int32(self[i].type.rawValue)
                    slots[i].enabled = self[i].enabled ? 1 : 0
                    slots[i].p1 = self[i].p1; slots[i].p2 = self[i].p2
                    slots[i].p3 = self[i].p3; slots[i].p4 = self[i].p4
                }
            }
        }
        return chain
    }
}
