//
//  PatternStudioView.swift
//  Decluttered multi-track Studio. Portrait stacks compact control rows above a
//  big scrollable piano-roll / drum-lanes canvas; rotating to landscape gives the
//  editor a wide layout. Key/scale/tempo live in a settings sheet; per-layer
//  actions live in menus — keeping the surface thumb-friendly.
//

import SwiftUI

struct PatternStudioView: View {
    @ObservedObject var transport: TransportController
    @State private var melodyMode: MelodyMode = .roll
    @State private var showSettings = false
    @State private var showBrowser = false
    @State private var showSoundLab = false
    @State private var midiExport: MidiExportItem?
    @State private var confirmClear = false
    @State private var confirmSpark = false
    @State private var confirmRemoveLayer: UUID?
    @EnvironmentObject var toast: ToastCenter
    @Environment(\.verticalSizeClass) private var vSize

    enum MelodyMode: String, CaseIterable { case roll = "Roll", play = "Pads" }

    private var melodicSelected: Bool {
        if case .track = transport.selection, transport.selectedLayer?.kind == .synth { return true }
        return false
    }

    var body: some View {
        ZStack {
            ArcticBackground(glow: transport.isPlaying)
            if vSize == .compact {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(transport: transport) }
        .sheet(isPresented: $showBrowser) {
            PatchBrowserView(transport: transport) {
                showBrowser = false
                showSoundLab = true
            }
        }
        .fullScreenCover(isPresented: $showSoundLab) { SoundLabView(transport: transport) }
        .sheet(item: $midiExport) { item in ShareSheet(url: item.url).presentationDetents([.medium]) }
        .confirmationDialog("Spark a new idea? This replaces the notes in this pattern.",
                            isPresented: $confirmSpark, titleVisibility: .visible) {
            Button("Spark new idea") { spark() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(clearDialogTitle, isPresented: $confirmClear, titleVisibility: .visible) {
            Button(clearLabel, role: .destructive) {
                transport.clearCurrent()
                toast.show(transport.selection == .drums ? "All drum lanes cleared" : "Layer cleared",
                           icon: "trash.circle.fill")
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove this layer? Its notes are deleted from every pattern.",
                            isPresented: Binding(get: { confirmRemoveLayer != nil },
                                                 set: { if !$0 { confirmRemoveLayer = nil } }),
                            titleVisibility: .visible) {
            Button("Remove layer", role: .destructive) {
                if let id = confirmRemoveLayer {
                    let name = transport.project.layers.first { $0.id == id }?.displayName ?? "Layer"
                    transport.removeTrack(id)
                    toast.show("\"\(name)\" removed", icon: "trash.circle.fill")
                }
                confirmRemoveLayer = nil
            }
            Button("Cancel", role: .cancel) { confirmRemoveLayer = nil }
        }
        .onAppear {
            transport.onAppear()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["ABSOUND_TAB"] == "drums" { transport.selectDrums() }
            if env["ABSOUND_MELODY"] == "play" { melodyMode = .play }
            if env["ABSOUND_SHOW"] == "browser" { showBrowser = true }
            if env["ABSOUND_SHOW"] == "soundlab" { showSoundLab = true }
            if env["ABSOUND_AUTOPLAY"] != nil { transport.playPattern() }
            #endif
        }
    }

    // MARK: - Portrait

    private var portraitBody: some View {
        VStack(spacing: 10) {
            topBar
            LayerStrip(transport: transport,
                       editSound: { transport.select($0); showSoundLab = true },
                       changeSound: { transport.select($0); showBrowser = true })
            contextualControls
            editorArea.frame(maxHeight: .infinity)
            transportBar
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
    }

    private func sparkTapped() {
        if transport.patternHasContent { confirmSpark = true } else { spark() }
    }
    private func spark() {
        transport.sparkIdea()
        if !transport.isPlaying { transport.playPattern() }   // hear it immediately
        toast.show("New idea sparked — tap ✨ to reroll", icon: "sparkles")
    }

    private var clearLabel: String {
        transport.selection == .drums ? "Clear all drums" : "Clear this layer"
    }
    private var clearDialogTitle: String {
        transport.selection == .drums
            ? "Clear every drum lane in this pattern?"
            : "Clear all notes on this layer in this pattern?"
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { showSettings = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "key").font(.system(size: 11))
                    Text(transport.context.displayName).font(Theme.body(14)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }
                .foregroundStyle(Theme.frost)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
            }
            .fixedSize()
            Spacer(minLength: 6)
            PatternChips(transport: transport)
            Menu {
                Button { transport.addPattern() } label: { Label("Add pattern", systemImage: "plus") }
                Button { transport.duplicatePattern() } label: { Label("Duplicate pattern", systemImage: "doc.on.doc") }
                Divider()
                Button {
                    if let url = MidiExport.export(transport.project) { midiExport = MidiExportItem(url: url) }
                } label: { Label("Export MIDI", systemImage: "square.and.arrow.up") }
                Divider()
                Button(role: .destructive) { confirmClear = true } label: {
                    Label(clearLabel, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.frost)
                    .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.07)))
            }
        }
    }

    @ViewBuilder private var contextualControls: some View {
        if melodicSelected, let layer = transport.selectedLayer {
            HStack(spacing: 8) {
                Button { showBrowser = true } label: {
                    pill(transport.selectedPatch?.name ?? "Sound", icon: "waveform")
                }
                Picker("", selection: $melodyMode) {
                    ForEach(MelodyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 130)
                if transport.isRecording {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                        .shadow(color: .red.opacity(0.8), radius: 2)
                }
                Spacer()
                layerMenu(layer)
            }
        } else if case .drums = transport.selection {
            DrumLaneControls(transport: transport, requestRemove: { confirmRemoveLayer = $0 })
        }
    }

    private func layerMenu(_ layer: Layer) -> some View {
        Menu {
            Button { showSoundLab = true } label: { Label("Edit sound", systemImage: "slider.vertical.3") }
            Button { showBrowser = true } label: { Label("Change sound", systemImage: "waveform") }
            Divider()
            Button {
                transport.generateMelody()
                toast.show("New melody generated", icon: "sparkles")
            } label: { Label("Generate melody", systemImage: "sparkles") }
            Button { transport.showShadow.toggle() } label: {
                Label(transport.showShadow ? "Hide other layers" : "Show other layers", systemImage: "square.stack.3d.up")
            }
            Button { transport.toggleMute(layer.id) } label: {
                Label(layer.muted ? "Unmute" : "Mute", systemImage: layer.muted ? "speaker.slash" : "speaker.wave.2")
            }
            Button { transport.toggleSolo(layer.id) } label: {
                Label(layer.soloed ? "Unsolo" : "Solo", systemImage: "headphones")
            }
            Divider()
            Button(role: .destructive) { confirmRemoveLayer = layer.id } label: { Label("Remove layer", systemImage: "minus.circle") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(Theme.frost.opacity(0.85))
                .frame(width: 38, height: 34)
        }
    }

    @ViewBuilder private var editorArea: some View {
        switch transport.selection {
        case .drums:
            DrumLanesView(transport: transport)
        case .track:
            if transport.selectedLayer != nil {
                switch melodyMode {
                case .roll: PianoRollView(transport: transport)
                case .play: AuroraHighwayView(transport: transport)
                }
            } else { Spacer() }
        }
    }

    private var transportBar: some View {
        HStack(spacing: 14) {
            playButton(size: 56)
            VStack(alignment: .leading, spacing: 1) {
                Text(transport.songPlaying ? "SONG" : "PATTERN")
                    .font(Theme.light(10)).foregroundStyle(Theme.frost.opacity(0.45)).tracking(2)
                Text(transport.songPlaying ? transport.project.name
                     : (transport.patternNames.indices.contains(transport.editIndex)
                        ? transport.patternNames[transport.editIndex] : ""))
                    .font(Theme.title(15)).foregroundStyle(Theme.frost.opacity(0.85)).lineLimit(1)
            }
            Spacer()
            Button { sparkTapped() } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.bgTop)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(
                        LinearGradient(colors: [Theme.cyan, Theme.teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .shadow(color: Theme.cyan.opacity(0.5), radius: 6)
            }
            Spacer()
            HStack(spacing: 12) {
                tempoButton("minus", -1)
                Text("\(Int(transport.tempo))").font(Theme.display(26)).foregroundStyle(Theme.frost).monospacedDigit().frame(width: 54)
                tempoButton("plus", 1)
            }
        }
        .padding(.vertical, 11).padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.frost.opacity(0.12), lineWidth: 1)))
    }

    // MARK: - Landscape (wide editor)

    private var landscapeBody: some View {
        HStack(spacing: 10) {
            VStack(spacing: 10) {
                playButton(size: 52)
                if melodicSelected {
                    Picker("", selection: $melodyMode) {
                        ForEach(MelodyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                Menu {
                    ForEach(transport.melodicLayers) { l in Button(l.displayName) { transport.select(l.id) } }
                    Button("Drums") { transport.selectDrums() }
                } label: { pill(transport.selectedLayer?.displayName ?? "Drums", icon: "rectangle.stack") }
                Button { showSettings = true } label: { pill("\(transport.context.rootName) · \(Int(transport.tempo))", icon: "key") }
                Spacer()
            }
            .frame(width: 132)
            editorArea
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Shared bits

    private func playButton(size: CGFloat) -> some View {
        Button(action: transport.togglePlay) {
            Image(systemName: transport.isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Theme.bgTop)
                .frame(width: size, height: size).background(Circle().fill(Theme.teal))
                .shadow(color: Theme.teal.opacity(transport.isPlaying ? 0.7 : 0.3), radius: 12)
        }
    }
    private func tempoButton(_ symbol: String, _ delta: Double) -> some View {
        Button { transport.setTempo(transport.tempo + delta) } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.frost)
                .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.08)))
        }
    }
    private func pill(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(Theme.body(14)).lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(Theme.frost)
        .padding(.vertical, 8).padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
    }
}

// MARK: - Pattern chips

private struct PatternChips: View {
    @ObservedObject var transport: TransportController
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(transport.patternNames.enumerated()), id: \.offset) { idx, name in
                    Button { transport.selectPattern(idx) } label: {
                        Text(name).font(Theme.title(15))
                            .foregroundStyle(transport.editIndex == idx ? Theme.bgTop : Theme.frost.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(transport.editIndex == idx ? Theme.teal.opacity(0.9) : Color.white.opacity(0.07)))
                    }
                }
            }
        }
    }
}

// MARK: - Layer selection strip

private struct LayerStrip: View {
    @ObservedObject var transport: TransportController
    var editSound: (UUID) -> Void = { _ in }
    var changeSound: (UUID) -> Void = { _ in }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(transport.melodicLayers) { l in
                    chip(l.displayName, selected: transport.selectedLayerId == l.id,
                         muted: l.muted, soloed: l.soloed, accent: Theme.cyan) { transport.select(l.id) }
                        .contextMenu {
                            Button { editSound(l.id) } label: { Label("Edit sound", systemImage: "slider.vertical.3") }
                            Button { changeSound(l.id) } label: { Label("Change sound", systemImage: "waveform") }
                            Divider()
                            Button { transport.toggleMute(l.id) } label: {
                                Label(l.muted ? "Unmute" : "Mute", systemImage: l.muted ? "speaker.slash" : "speaker.wave.2")
                            }
                            Button { transport.toggleSolo(l.id) } label: {
                                Label(l.soloed ? "Unsolo" : "Solo", systemImage: "headphones")
                            }
                        }
                }
                chip("Drums", selected: transport.selection == .drums, muted: false, soloed: false, accent: Theme.teal) { transport.selectDrums() }
                Menu {
                    Menu("Add instrument") {
                        ForEach(PatchCategory.allCases) { cat in
                            Menu(cat.rawValue) {
                                ForEach(PatchFactory.presets.filter { $0.category == cat }) { p in
                                    Button(p.name) { transport.addSynthLayer(p) }
                                }
                            }
                        }
                    }
                    Menu("Add drum") { ForEach(DrumSound.allCases) { d in Button(d.name) { transport.addDrumLayer(d) } } }
                } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.frost)
                        .frame(width: 38, height: 34).background(Capsule().fill(Color.white.opacity(0.07)))
                }
            }
        }
    }
    private func chip(_ title: String, selected: Bool, muted: Bool, soloed: Bool, accent: Color, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                if muted { Image(systemName: "speaker.slash.fill").font(.system(size: 9)) }
                if soloed { Image(systemName: "headphones").font(.system(size: 9)) }
                Text(title).font(Theme.body(14))
            }
            .foregroundStyle(selected ? Theme.bgTop : Theme.frost.opacity(muted ? 0.4 : 0.85))
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(Capsule().fill(selected ? accent.opacity(0.9) : Color.white.opacity(0.07)))
            .overlay(Capsule().stroke(soloed ? Theme.teal : .clear, lineWidth: 1.5))
        }
    }
}

// MARK: - Drum lane controls (sound/mute/remove per lane)

private struct DrumLaneControls: View {
    @ObservedObject var transport: TransportController
    var requestRemove: (UUID) -> Void = { _ in }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(transport.drumLayers) { t in
                    Menu {
                        ForEach(DrumSound.allCases) { d in Button(d.name) { transport.setTrackSound(t.id, sound: d.rawValue) } }
                        Divider()
                        Button { transport.toggleMute(t.id) } label: { Label(t.muted ? "Unmute" : "Mute", systemImage: t.muted ? "speaker.slash" : "speaker.wave.2") }
                        Button { transport.toggleSolo(t.id) } label: { Label(t.soloed ? "Unsolo" : "Solo", systemImage: "headphones") }
                        Button(role: .destructive) { requestRemove(t.id) } label: { Label("Remove", systemImage: "trash") }
                    } label: {
                        HStack(spacing: 3) {
                            Text(t.displayName).font(Theme.body(13)); Image(systemName: "chevron.down").font(.system(size: 8))
                        }
                        .foregroundStyle(t.muted ? Theme.frost.opacity(0.4) : Theme.frost.opacity(0.85))
                        .padding(.vertical, 7).padding(.horizontal, 11)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                }
                Menu { ForEach(DrumSound.allCases) { d in Button(d.name) { transport.addDrumLayer(d) } } } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.teal)
                        .frame(width: 34, height: 32).background(Capsule().fill(Color.white.opacity(0.07)))
                }
            }
        }
    }
}

// MARK: - Settings sheet (key / scale / tempo)

private struct SettingsSheet: View {
    @ObservedObject var transport: TransportController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    Picker("Root", selection: Binding(get: { transport.context.root }, set: { transport.setRoot($0) })) {
                        ForEach(0..<12, id: \.self) { Text(MusicalContext.rootNames[$0]).tag($0) }
                    }
                    Picker("Scale", selection: Binding(get: { transport.context.scale }, set: { transport.setScale($0) })) {
                        ForEach(Scale.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Tempo") {
                    Stepper("\(Int(transport.tempo)) BPM", value: Binding(get: { transport.tempo }, set: { transport.setTempo($0) }), in: 60...200)
                }
            }
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

#Preview { PatternStudioView(transport: TransportController()) }
