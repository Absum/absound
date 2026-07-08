//
//  SoundsTabView.swift
//  Direct entry to sound design: browse My Sounds + the factory library and open
//  the Sound Lab standalone — no layer required. Auditions play through the
//  engine's dedicated preview track; saves land in My Sounds.
//

import SwiftUI

struct SoundsTabView: View {
    @ObservedObject var transport: TransportController
    @EnvironmentObject var library: PatchLibrary
    @EnvironmentObject var toast: ToastCenter

    @State private var labPatch: SynthPatch?
    @State private var renameTarget: SynthPatch?
    @State private var deleteTarget: SynthPatch?
    @State private var newName = ""

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        ZStack {
            ArcticBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    mySounds
                    ForEach(PatchCategory.allCases) { cat in
                        let patches = PatchFactory.presets.filter { $0.category == cat }
                        VStack(alignment: .leading, spacing: 8) {
                            Label(cat.rawValue, systemImage: cat.icon)
                                .font(Theme.title(15)).foregroundStyle(Theme.teal)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(patches) { p in card(p) }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .fullScreenCover(item: $labPatch) { p in
            SoundLabView(transport: transport, standalone: true, initialPatch: p)
        }
        .alert("Rename sound", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let t = renameTarget {
                    library.rename(t.id, to: newName)
                    toast.show("Renamed to \"\(newName)\"", icon: "pencil.circle.fill")
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog("Delete \"\(deleteTarget?.name ?? "")\"? Layers using it keep their copy.",
                            isPresented: Binding(get: { deleteTarget != nil },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete sound", role: .destructive) {
                if let t = deleteTarget {
                    library.delete(t.id)
                    toast.show("\"\(t.name)\" deleted", icon: "trash.circle.fill")
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        }
        .onAppear { transport.onAppear() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SOUNDS").font(Theme.display(24)).foregroundStyle(Theme.frost).tracking(4)
            Text("Tap any sound to shape it in the Sound Lab — no layer needed")
                .font(Theme.light(12)).foregroundStyle(Theme.frost.opacity(0.45))
        }
    }

    @ViewBuilder private var mySounds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("My Sounds", systemImage: "person.fill")
                .font(Theme.title(15)).foregroundStyle(Theme.cyan)
            if library.userPatches.isEmpty {
                Text("Nothing here yet — open any sound below, shape it, and Save to My Sounds.")
                    .font(Theme.body(13)).foregroundStyle(Theme.frost.opacity(0.4))
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(library.userPatches) { p in
                        card(p)
                            .contextMenu {
                                Button { newName = p.name; renameTarget = p } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) { deleteTarget = p } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                Text("Hold a sound to rename or delete")
                    .font(Theme.light(10)).foregroundStyle(Theme.frost.opacity(0.35))
            }
        }
    }

    private func card(_ p: SynthPatch) -> some View {
        Button { labPatch = p } label: {
            VStack(spacing: 6) {
                Image(systemName: p.category.icon)
                    .font(.system(size: 18)).foregroundStyle(Theme.cyan)
                Text(p.name)
                    .font(Theme.body(13)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(Theme.frost)
            }
            .frame(maxWidth: .infinity).frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.frost.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
