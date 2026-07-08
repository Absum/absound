//
//  FXChainView.swift
//  The insert-FX chain editor: ordered slot cards in signal flow, each with an
//  enable toggle, per-effect named knobs, and drag-to-reorder. Used by the
//  Sound Lab (per-sound chain) and the Mix tab (per-sound + master chains).
//
//  Reordering works on a local working copy: mutating the live binding during a
//  drag rebuilds the whole tree (transport publishes) and cancels the drop
//  session — the "stuck dimmed card" bug. The working copy renders and moves;
//  the binding is committed once, on drop (with catch-alls so a missed drop
//  can never leave the UI stuck or the engine stale).
//

import SwiftUI

struct FXChainView: View {
    @Binding var chain: [FXSlot]

    @State private var working: [FXSlot] = []
    @State private var draggedSlot: UUID?
    @State private var confirmRemove: UUID?
    @EnvironmentObject var toast: ToastCenter

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(working.enumerated()), id: \.element.id) { idx, slot in
                slotCard(idx: idx, slot: slot)
                    .opacity(draggedSlot == slot.id ? 0.4 : 1)
                    .onDrag {
                        draggedSlot = slot.id
                        return NSItemProvider(object: slot.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: FXReorderDelegate(
                        item: slot.id, working: $working, dragged: $draggedSlot, commit: commit))
            }
            if working.count < Int(AB_MAX_FX) {
                Menu {
                    ForEach(FXType.allCases) { t in
                        Button { working.append(FXSlot(type: t)); commit() } label: { Label(t.name, systemImage: t.icon) }
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
            if working.isEmpty {
                Text("No effects — the signal passes through clean")
                    .font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.35))
            }
        }
        // Catch-all: a drop that lands between cards still commits and un-dims.
        .onDrop(of: [.text], isTargeted: nil) { _ in commit(); return true }
        // Rescue: if a drag session dies without any drop event, the next tap clears it.
        .simultaneousGesture(TapGesture().onEnded { if draggedSlot != nil { commit() } })
        .confirmationDialog(
            "Remove \(working.first { $0.id == confirmRemove }?.type.name ?? "this effect") from the chain?",
            isPresented: Binding(get: { confirmRemove != nil },
                                 set: { if !$0 { confirmRemove = nil } }),
            titleVisibility: .visible) {
            Button("Remove effect", role: .destructive) {
                if let id = confirmRemove, let i = working.firstIndex(where: { $0.id == id }) {
                    let name = working[i].type.name
                    working.remove(at: i)
                    commit()
                    toast.show("\(name) removed", icon: "trash.circle.fill")
                }
                confirmRemove = nil
            }
            Button("Cancel", role: .cancel) { confirmRemove = nil }
        }
        .onAppear { working = chain }
        .onChange(of: chain) { _, newValue in
            if draggedSlot == nil && newValue != working { working = newValue }
        }
    }

    /// Push the working order/params to the real binding (engine + persistence)
    /// and end any drag state.
    private func commit() {
        draggedSlot = nil
        if chain != working { chain = working }
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
                    get: { working.indices.contains(idx) ? working[idx].enabled : true },
                    set: { if working.indices.contains(idx) { working[idx].enabled = $0; commit() } }
                ))
                .labelsHidden().tint(Theme.teal).scaleEffect(0.75)
                Menu {
                    Menu("Change effect") {
                        ForEach(FXType.allCases) { t in
                            Button { if working.indices.contains(idx) { working[idx] = FXSlot(type: t); commit() } } label: {
                                Label(t.name, systemImage: t.icon)
                            }
                        }
                    }
                    if idx > 0 {
                        Button { working.swapAt(idx, idx - 1); commit() } label: { Label("Move earlier", systemImage: "arrow.up") }
                    }
                    if idx < working.count - 1 {
                        Button { working.swapAt(idx, idx + 1); commit() } label: { Label("Move later", systemImage: "arrow.down") }
                    }
                    Button(role: .destructive) { confirmRemove = slot.id } label: { Label("Remove", systemImage: "trash") }
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
                                           get: { working.indices.contains(idx) ? working[idx][param: p] : spec.def },
                                           set: {
                                               if working.indices.contains(idx) {
                                                   working[idx][param: p] = $0
                                                   if draggedSlot == nil && chain != working { chain = working }
                                               }
                                           }
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

/// Live-reorders the *working copy* as a dragged card hovers; the binding is
/// committed once on drop.
private struct FXReorderDelegate: DropDelegate {
    let item: UUID
    @Binding var working: [FXSlot]
    @Binding var dragged: UUID?
    let commit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != item,
              let from = working.firstIndex(where: { $0.id == dragged }),
              let to = working.firstIndex(where: { $0.id == item }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            working.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { commit(); return true }
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
