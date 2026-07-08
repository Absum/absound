//
//  FXChainView.swift
//  The insert-FX chain editor: ordered slot cards in signal flow, each with an
//  enable toggle, per-effect named knobs, and a menu to change/move/remove.
//  Used by the Sound Lab (per-sound chain) and the Mix tab (master chain).
//

import SwiftUI

struct FXChainView: View {
    @Binding var chain: [FXSlot]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(chain.enumerated()), id: \.element.id) { idx, slot in
                slotCard(idx: idx, slot: slot)
            }
            if chain.count < Int(AB_MAX_FX) {
                Menu {
                    ForEach(FXType.allCases) { t in
                        Button { chain.append(FXSlot(type: t)) } label: { Label(t.name, systemImage: t.icon) }
                    }
                } label: {
                    Label("Add effect", systemImage: "plus")
                        .font(Theme.body(14)).foregroundStyle(Theme.teal)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.teal.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
            }
            if chain.isEmpty {
                Text("No effects — the signal passes through clean")
                    .font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.35))
            }
        }
    }

    private func slotCard(idx: Int, slot: FXSlot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10)).foregroundStyle(Theme.frost.opacity(0.25))
                Label(slot.type.name, systemImage: slot.type.icon)
                    .font(Theme.title(14)).foregroundStyle(slot.enabled ? Theme.cyan : Theme.frost.opacity(0.35))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { chain.indices.contains(idx) ? chain[idx].enabled : true },
                    set: { if chain.indices.contains(idx) { chain[idx].enabled = $0 } }
                ))
                .labelsHidden().tint(Theme.teal).scaleEffect(0.75)
                Menu {
                    Menu("Change effect") {
                        ForEach(FXType.allCases) { t in
                            Button { if chain.indices.contains(idx) { chain[idx] = FXSlot(type: t) } } label: {
                                Label(t.name, systemImage: t.icon)
                            }
                        }
                    }
                    if idx > 0 {
                        Button { chain.swapAt(idx, idx - 1) } label: { Label("Move earlier", systemImage: "arrow.up") }
                    }
                    if idx < chain.count - 1 {
                        Button { chain.swapAt(idx, idx + 1) } label: { Label("Move later", systemImage: "arrow.down") }
                    }
                    Button(role: .destructive) { chain.remove(at: idx) } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.frost.opacity(0.7))
                }
            }
            if slot.enabled {
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { p in
                        if let spec = slot.type.params[safeIndex: p] ?? nil {
                            ArcticKnob(spec.label,
                                       value: Binding(
                                           get: { chain.indices.contains(idx) ? chain[idx][param: p] : spec.def },
                                           set: { if chain.indices.contains(idx) { chain[idx][param: p] = $0 } }
                                       ),
                                       range: spec.range,
                                       curve: spec.log ? .log : .linear,
                                       format: spec.format)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(slot.enabled ? 0.06 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.frost.opacity(0.1), lineWidth: 1))
    }
}

/// Compact, read-only chain summary (Simple view / mixer strips).
struct FXChainSummary: View {
    let chain: [FXSlot]
    var body: some View {
        HStack(spacing: 6) {
            if chain.isEmpty {
                Text("No effects").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.35))
            } else {
                ForEach(chain) { s in
                    Image(systemName: s.type.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(s.enabled ? Theme.cyan : Theme.frost.opacity(0.3))
                }
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(Theme.frost.opacity(0.3))
            }
        }
    }
}

private extension Array {
    subscript(safeIndex i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
