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
    @EnvironmentObject var toast: ToastCenter
    @State private var showSongs = false
    @State private var confirmClearSong = false
    @State private var confirmRemoveSection: UUID?
    @State private var midiExport: MidiExportItem?
    @State private var workingSong: [SectionItem] = []
    @State private var draggedSection: UUID?
    @State private var dropSessionActive = false

    struct SectionItem: Identifiable, Equatable {
        let id: UUID
        var pattern: Int
    }

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
        .confirmationDialog(
            "Remove this section from the arrangement?",
            isPresented: Binding(get: { confirmRemoveSection != nil },
                                 set: { if !$0 { confirmRemoveSection = nil } }),
            titleVisibility: .visible) {
            Button("Remove section", role: .destructive) {
                if let id = confirmRemoveSection,
                   let i = workingSong.firstIndex(where: { $0.id == id }) {
                    transport.removeSection(at: i)
                    toast.show("Section removed", icon: "trash.circle.fill")
                }
                confirmRemoveSection = nil
            }
            Button("Cancel", role: .cancel) { confirmRemoveSection = nil }
        }
        .confirmationDialog("Clear the whole arrangement? (Patterns are kept.)",
                            isPresented: $confirmClearSong, titleVisibility: .visible) {
            Button("Clear arrangement", role: .destructive) {
                transport.clearSong()
                toast.show("Arrangement cleared", icon: "trash.circle.fill")
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            transport.onAppear()
            syncWorkingSong()
        }
        .onChange(of: transport.project.song) { _, _ in
            if draggedSection == nil { syncWorkingSong() }
        }
    }

    private func syncWorkingSong() {
        // Rebuild only when the pattern sequence actually differs, to keep ids stable.
        if workingSong.map(\.pattern) != song {
            workingSong = song.map { SectionItem(id: UUID(), pattern: $0) }
        }
    }

    private func commitOrder() {
        draggedSection = nil
        let order = workingSong.map(\.pattern)
        if order != song {
            transport.setSongOrder(order)
            toast.show("Arrangement reordered", icon: "arrow.left.arrow.right.circle.fill")
        }
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
                    Text("tap to remove · hold to reorder").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.35))
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
                        ForEach(Array(workingSong.enumerated()), id: \.element.id) { i, item in
                            let playing = transport.songPlaying && playhead.songPosition == i
                            Button {
                                confirmRemoveSection = item.id
                            } label: {
                                Text(names.indices.contains(item.pattern) ? names[item.pattern] : "?")
                                    .font(Theme.title(18))
                                    .foregroundStyle(playing ? Theme.bgTop : Theme.frost)
                                    .frame(width: 52, height: 70)
                                    .background(RoundedRectangle(cornerRadius: 10)
                                        .fill(playing ? Theme.teal.opacity(0.95) : Color.white.opacity(0.08)))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.frost.opacity(0.15), lineWidth: 1))
                                    .shadow(color: playing ? Theme.teal.opacity(0.7) : .clear, radius: 8)
                            }
                            .opacity(draggedSection == item.id ? 0.4 : 1)
                            .onDrag {
                                draggedSection = item.id
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: SectionReorderDelegate(
                                item: item.id, working: $workingSong, dragged: $draggedSection, commit: commitOrder))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDrop(of: [.text], isTargeted: $dropSessionActive) { _ in commitOrder(); return true }
                .onChange(of: dropSessionActive) { _, active in
                    // The session signal reliably ends when the finger lifts anywhere —
                    // commit + un-dim even when performDrop never fires (SwiftUI wart).
                    if !active && draggedSection != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { commitOrder() }
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { if draggedSection != nil { commitOrder() } })
            }
        }
    }

    // MARK: - Songs library sheet

    private struct SongsSheet: View {
        @ObservedObject var transport: TransportController
        @EnvironmentObject var library: SongLibrary
        @EnvironmentObject var toast: ToastCenter
        @Environment(\.dismiss) private var dismiss

        @State private var renameTarget: Project?
        @State private var deleteTarget: Project?
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
                                toast.show("\"\(transport.project.name)\" saved to library")
                            } label: {
                                Label("Save to library", systemImage: "square.and.arrow.down")
                                    .foregroundStyle(Theme.teal)
                            }
                            Button {
                                stashCurrent()
                                transport.loadProject(Project.blank(name: library.uniqueName("New Song")))
                                toast.show("New song — previous saved to library", icon: "plus.circle.fill")
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
                                    toast.show("Loaded \"\(s.name)\"", icon: "folder.circle.fill")
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
                                    Button(role: .destructive) { deleteTarget = s } label: { Label("Delete", systemImage: "trash") }
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
                            toast.show("Renamed to \"\(newName)\"", icon: "pencil.circle.fill")
                        } else if let t = renameTarget {
                            library.rename(t.id, to: newName)
                            toast.show("Renamed to \"\(newName)\"", icon: "pencil.circle.fill")
                        }
                        renameTarget = nil; renamingCurrent = false
                    }
                    Button("Cancel", role: .cancel) { renameTarget = nil; renamingCurrent = false }
                }
                .confirmationDialog("Delete \"\(deleteTarget?.name ?? "")\" from the library? This cannot be undone.",
                                    isPresented: Binding(get: { deleteTarget != nil },
                                                         set: { if !$0 { deleteTarget = nil } }),
                                    titleVisibility: .visible) {
                    Button("Delete song", role: .destructive) {
                        if let t = deleteTarget {
                            library.delete(t.id)
                            toast.show("\"\(t.name)\" deleted", icon: "trash.circle.fill")
                        }
                        deleteTarget = nil
                    }
                    Button("Cancel", role: .cancel) { deleteTarget = nil }
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
                HStack(spacing: 8) {
                    Button { transport.setTempo(transport.tempo - 1) } label: {
                        Image(systemName: "minus").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.frost.opacity(0.7)).frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    Text("\(Int(transport.tempo)) BPM").font(Theme.light(12)).foregroundStyle(Theme.frost.opacity(0.6)).monospacedDigit()
                    Button { transport.setTempo(transport.tempo + 1) } label: {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.frost.opacity(0.7)).frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                }
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
                Button { confirmClearSong = true } label: {
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


/// Live-reorders the working arrangement as a dragged section hovers; committed on drop.
private struct SectionReorderDelegate: DropDelegate {
    let item: UUID
    @Binding var working: [SongArrangerView.SectionItem]
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
