//
//  SongArrangerView.swift
//  The Song tab: chain patterns into a full-length arrangement. Tap a pattern to
//  append a section; the sequence plays through, highlighting the current pattern.
//  Shares the Studio's TransportController, so edits to a pattern show everywhere
//  it is used.
//

import SwiftUI

struct SongArrangerView: View {
    @ObservedObject var transport: TransportController
    @ObservedObject var playhead: PlayheadState

    init(transport: TransportController) {
        self.transport = transport
        self.playhead = transport.playhead
    }
    @EnvironmentObject var songLibrary: SongLibrary
    @State private var showSongs = false
    @State private var midiExport: MidiExportItem?

    private var song: [Int] { transport.project.song }
    private var names: [String] { transport.patternNames }

    var body: some View {
        ZStack {
            ArcticBackground(glow: transport.songPlaying)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SONG").font(Theme.display(24)).foregroundStyle(Theme.frost).tracking(4)
                        Text(transport.project.name).font(Theme.body(13)).foregroundStyle(Theme.teal)
                    }
                    Spacer()
                    Button { showSongs = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder").font(.system(size: 12))
                            Text("Songs").font(Theme.body(14))
                        }
                        .foregroundStyle(Theme.frost)
                        .padding(.vertical, 8).padding(.horizontal, 13)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                }

                palette
                arrangement
                Spacer()
                transportRow
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        }
        .sheet(isPresented: $showSongs) { SongsSheet(transport: transport) }
        .sheet(item: $midiExport) { item in
            ShareSheet(url: item.url)
                .presentationDetents([.medium])
        }
        .onAppear { transport.onAppear() }
    }

    // Tap a pattern to append it as a section.
    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PATTERNS — tap to add a section").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5)).tracking(1)
            HStack(spacing: 8) {
                ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                    Button { transport.appendSection(idx) } label: {
                        Text(name).font(Theme.title(18)).foregroundStyle(Theme.frost)
                            .frame(width: 46, height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cyan.opacity(0.18)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.frost.opacity(0.18), lineWidth: 1))
                    }
                }
            }
        }
    }

    private var arrangement: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ARRANGEMENT").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5)).tracking(1)
                Spacer()
                if !song.isEmpty {
                    Text("tap a section to remove").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.35))
                }
            }
            if song.isEmpty {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
                    .frame(height: 70)
                    .overlay(Text("Add patterns above to build your song")
                        .font(Theme.body(14)).foregroundStyle(Theme.frost.opacity(0.4)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(song.enumerated()), id: \.offset) { i, patternIdx in
                            let playing = transport.songPlaying && playhead.songPosition == i
                            Button { transport.removeSection(at: i) } label: {
                                Text(names.indices.contains(patternIdx) ? names[patternIdx] : "?")
                                    .font(Theme.title(18))
                                    .foregroundStyle(playing ? Theme.bgTop : Theme.frost)
                                    .frame(width: 52, height: 70)
                                    .background(RoundedRectangle(cornerRadius: 10)
                                        .fill(playing ? Theme.teal.opacity(0.95) : Color.white.opacity(0.08)))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.frost.opacity(0.15), lineWidth: 1))
                                    .shadow(color: playing ? Theme.teal.opacity(0.7) : .clear, radius: 8)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Songs library sheet

    private struct SongsSheet: View {
        @ObservedObject var transport: TransportController
        @EnvironmentObject var library: SongLibrary
        @Environment(\.dismiss) private var dismiss

        @State private var renameTarget: Project?
        @State private var newName = ""
        @State private var renamingCurrent = false

        var body: some View {
            NavigationStack {
                ZStack {
                    Theme.bgGradient.ignoresSafeArea()
                    List {
                        Section("Current song") {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(transport.project.name).font(Theme.body(16)).foregroundStyle(Theme.frost)
                                    Text(library.contains(transport.project.id) ? "In library" : "Not saved to library")
                                        .font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.4))
                                }
                                Spacer()
                                Button { newName = transport.project.name; renamingCurrent = true } label: {
                                    Image(systemName: "pencil").foregroundStyle(Theme.frost.opacity(0.7))
                                }
                                .buttonStyle(.borderless)
                            }
                            Button {
                                library.save(transport.project)
                            } label: {
                                Label("Save to library", systemImage: "square.and.arrow.down")
                                    .foregroundStyle(Theme.teal)
                            }
                            Button {
                                stashCurrent()
                                transport.loadProject(Project.blank(name: library.uniqueName("New Song")))
                                dismiss()
                            } label: {
                                Label("New song", systemImage: "plus").foregroundStyle(Theme.cyan)
                            }
                        }
                        Section("Library") {
                            if library.songs.isEmpty {
                                Text("No saved songs yet").font(Theme.body(13)).foregroundStyle(Theme.frost.opacity(0.4))
                            }
                            ForEach(library.songs) { s in
                                Button {
                                    guard s.id != transport.project.id else { dismiss(); return }
                                    stashCurrent()
                                    transport.loadProject(s)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(s.name).font(Theme.body(15)).foregroundStyle(Theme.frost)
                                        Spacer()
                                        if s.id == transport.project.id {
                                            Text("current").font(Theme.light(11)).foregroundStyle(Theme.teal)
                                        }
                                        Text("\(s.song.count) section\(s.song.count == 1 ? "" : "s")")
                                            .font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.4))
                                    }
                                }
                                .contextMenu {
                                    Button { newName = s.name; renameTarget = s } label: { Label("Rename", systemImage: "pencil") }
                                    Button(role: .destructive) { library.delete(s.id) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .navigationTitle("Songs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .alert("Rename song", isPresented: Binding(
                    get: { renameTarget != nil || renamingCurrent },
                    set: { if !$0 { renameTarget = nil; renamingCurrent = false } }
                )) {
                    TextField("Name", text: $newName)
                    Button("Rename") {
                        if renamingCurrent {
                            transport.renameProject(newName)
                            if library.contains(transport.project.id) { library.rename(transport.project.id, to: newName) }
                        } else if let t = renameTarget {
                            library.rename(t.id, to: newName)
                        }
                        renameTarget = nil; renamingCurrent = false
                    }
                    Button("Cancel", role: .cancel) { renameTarget = nil; renamingCurrent = false }
                }
            }
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }

        /// Nothing is ever lost: the current song is snapshotted into the library
        /// before switching away from it.
        private func stashCurrent() {
            library.save(transport.project)
        }
    }

    private var transportRow: some View {
        HStack(spacing: 18) {
            Button { transport.toggleSong() } label: {
                Image(systemName: transport.songPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.bgTop)
                    .frame(width: 58, height: 58).background(Circle().fill(Theme.teal))
                    .shadow(color: Theme.teal.opacity(transport.songPlaying ? 0.7 : 0.3), radius: 12)
            }
            .disabled(song.isEmpty)
            .opacity(song.isEmpty ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.isEmpty ? "No sections" : "\(song.count) section\(song.count == 1 ? "" : "s")")
                    .font(Theme.title(16)).foregroundStyle(Theme.frost)
                Text("\(Int(transport.tempo)) BPM").font(Theme.light(12)).foregroundStyle(Theme.frost.opacity(0.5))
            }
            Spacer()
            Button {
                if let url = MidiExport.export(transport.project) { midiExport = MidiExportItem(url: url) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 12))
                    Text("MIDI").font(Theme.body(14))
                }
                .foregroundStyle(Theme.cyan)
                .padding(.vertical, 9).padding(.horizontal, 14)
                .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            if !song.isEmpty {
                Button { transport.clearSong() } label: {
                    Text("Clear").font(Theme.body(14)).foregroundStyle(Theme.frost.opacity(0.7))
                        .padding(.vertical, 9).padding(.horizontal, 16)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
            }
        }
    }
}

// MARK: - MIDI share plumbing

struct MidiExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
