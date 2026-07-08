//
//  PatchBrowserView.swift
//  Factory-preset browser. Tap a card to apply it to the selected layer live
//  (audition while the loop plays); "Edit in Sound Lab" opens the full editor.
//

import SwiftUI

struct PatchBrowserView: View {
    @ObservedObject var transport: TransportController
    @EnvironmentObject var library: PatchLibrary
    var openSoundLab: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var renameTarget: SynthPatch?
    @State private var newName = ""

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        mySounds
                        ForEach(PatchCategory.allCases) { cat in
                            let patches = PatchFactory.presets.filter { $0.category == cat }
                            VStack(alignment: .leading, spacing: 8) {
                                Label(cat.rawValue, systemImage: cat.icon)
                                    .font(Theme.title(15))
                                    .foregroundStyle(Theme.teal)
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(patches) { p in card(p) }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .alert("Rename sound", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let t = renameTarget { library.rename(t.id, to: newName) }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .navigationTitle("Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { openSoundLab() } label: {
                        Label("Sound Lab", systemImage: "slider.vertical.3").font(Theme.body(14))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var mySounds: some View {
        if !library.userPatches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("My Sounds", systemImage: "person.fill")
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.cyan)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(library.userPatches) { p in
                        card(p)
                            .contextMenu {
                                Button { newName = p.name; renameTarget = p } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) { library.delete(p.id) } label: {
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
        let isCurrent = transport.selectedPatch?.id == p.id
        return Button {
            if let id = transport.selectedLayerId {
                transport.applyPatch(id, patch: p)
                transport.audition(row: transport.context.scale.degreeCount) // hear it immediately
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: p.category.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isCurrent ? Theme.bgTop : Theme.cyan)
                Text(p.name)
                    .font(Theme.body(13)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(isCurrent ? Theme.bgTop : Theme.frost)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? Theme.teal.opacity(0.9) : Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? Theme.teal : Theme.frost.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
