//
//  PatchBrowserView.swift
//  Factory-preset browser. Tap a card to apply it to the selected layer live
//  (audition while the loop plays); "Edit in Sound Lab" opens the full editor.
//

import SwiftUI

struct PatchBrowserView: View {
    @ObservedObject var transport: TransportController
    var openSoundLab: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
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

    private func card(_ p: SynthPatch) -> some View {
        let isCurrent = transport.selectedPatch?.name == p.name
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
