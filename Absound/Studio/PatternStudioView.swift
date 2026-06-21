//
//  PatternStudioView.swift
//  M-Layers Studio: a multi-track composer. A layer bar selects which track to
//  edit — melodic layers open the scale-locked Roll/Highway; the Drums chip opens
//  the multi-lane drum grid. Key/scale/tempo are global; each layer has its own
//  sound. Everything auditions live through the N-track engine.
//

import SwiftUI

struct PatternStudioView: View {
    @StateObject private var transport = TransportController()
    @State private var melodyMode: MelodyMode = .roll

    enum MelodyMode: String, CaseIterable { case roll = "Roll", play = "Play" }

    var body: some View {
        ZStack {
            ArcticBackground(glow: transport.isPlaying)
            VStack(spacing: 10) {
                header
                keyScaleBar
                LayerBar(transport: transport)
                editorArea
                    .frame(maxHeight: .infinity)
                TransportBar(transport: transport)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .onAppear {
            transport.onAppear()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["ABSOUND_TAB"] == "drums" { transport.selectDrums() }
            if env["ABSOUND_MELODY"] == "play" { melodyMode = .play }
            if env["ABSOUND_AUTOPLAY"] != nil { transport.play() }
            #endif
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ABSOUND").font(Theme.display(22)).foregroundStyle(Theme.frost).tracking(4)
            Spacer()
            Button { transport.clearCurrent() } label: {
                Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.frost.opacity(0.7))
            }
        }
    }

    private var keyScaleBar: some View {
        HStack(spacing: 8) {
            menu(label: transport.context.rootName, icon: "key") {
                ForEach(0..<12, id: \.self) { r in Button(MusicalContext.rootNames[r]) { transport.setRoot(r) } }
            }
            menu(label: transport.context.scale.displayName, icon: "music.note.list") {
                ForEach(Scale.allCases) { s in Button(s.displayName) { transport.setScale(s) } }
            }
        }
    }

    @ViewBuilder private var editorArea: some View {
        switch transport.selection {
        case .drums:
            DrumsEditor(transport: transport)
        case .track:
            if transport.selectedTrack != nil {
                MelodicEditor(transport: transport, mode: $melodyMode)
            } else {
                Spacer()
            }
        }
    }

    private func menu<Content: View>(label: String, icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        Menu { content() } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(Theme.body(15)).lineLimit(1)
            }
            .foregroundStyle(Theme.frost)
            .padding(.vertical, 8).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.frost.opacity(0.12), lineWidth: 1))
        }
    }
}

// MARK: - Layer bar

private struct LayerBar: View {
    @ObservedObject var transport: TransportController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(transport.melodicTracks) { t in
                    chip(title: t.displayName,
                         selected: transport.selectedTrackId == t.id,
                         muted: t.muted,
                         accent: Theme.cyan) { transport.select(t.id) }
                }
                chip(title: "Drums",
                     selected: transport.selection == .drums,
                     muted: false,
                     accent: Theme.teal) { transport.selectDrums() }
                addMenu
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, selected: Bool, muted: Bool, accent: Color, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                if muted { Image(systemName: "speaker.slash.fill").font(.system(size: 9)) }
                Text(title).font(Theme.body(14))
            }
            .foregroundStyle(selected ? Theme.bgTop : Theme.frost.opacity(muted ? 0.4 : 0.85))
            .padding(.vertical, 7).padding(.horizontal, 13)
            .background(Capsule().fill(selected ? accent.opacity(0.9) : Color.white.opacity(0.07)))
            .overlay(Capsule().stroke(Theme.frost.opacity(0.12), lineWidth: 1))
        }
    }

    private var addMenu: some View {
        Menu {
            Menu("Add instrument") {
                ForEach(SynthPreset.allCases) { p in Button(p.name) { transport.addSynthLayer(p) } }
            }
            Menu("Add drum") {
                ForEach(DrumSound.allCases) { d in Button(d.name) { transport.addDrumLayer(d) } }
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.frost)
                .frame(width: 36, height: 34)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().stroke(Theme.frost.opacity(0.12), lineWidth: 1))
        }
    }
}

// MARK: - Melodic editor (selected synth layer)

private struct MelodicEditor: View {
    @ObservedObject var transport: TransportController
    @Binding var mode: PatternStudioView.MelodyMode

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if let t = transport.selectedTrack {
                    Menu {
                        ForEach(SynthPreset.allCases) { p in Button(p.name) { transport.setTrackSound(t.id, sound: p.rawValue) } }
                    } label: {
                        chipLabel(transport.selectedPreset.name, icon: "waveform")
                    }
                    Button { transport.toggleMute(t.id) } label: {
                        Image(systemName: t.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(t.muted ? .red.opacity(0.8) : Theme.frost.opacity(0.8))
                            .frame(width: 38, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                    }
                    Button { transport.removeTrack(t.id) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.frost.opacity(0.6))
                            .frame(width: 38, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                    }
                    Button { transport.showShadow.toggle() } label: {
                        Image(systemName: transport.showShadow ? "square.stack.3d.up.fill" : "square.stack.3d.up.slash")
                            .foregroundStyle(transport.showShadow ? Theme.cyan : Theme.frost.opacity(0.5))
                            .frame(width: 38, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                    }
                }
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(PatternStudioView.MelodyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 150)
            }
            switch mode {
            case .roll: ScrollView { MelodyRoll(transport: transport) }
            case .play: AuroraHighwayView(transport: transport)
            }
        }
    }

    private func chipLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(Theme.body(14)).lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(Theme.frost)
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
    }
}

private struct MelodyRoll: View {
    @ObservedObject var transport: TransportController

    var body: some View {
        let ctx = transport.context
        let melody = transport.selectedMelody
        let others = transport.showShadow ? transport.otherMelodies : []
        let rows = Array((0..<transport.melodyRowCount).reversed())
        VStack(spacing: 3) {
            ForEach(rows, id: \.self) { row in
                let isRoot = (ctx.midiNote(forRow: row) - ctx.root) % 12 == 0
                HStack(spacing: 3) {
                    Text(ctx.noteName(forRow: row)).font(Theme.light(11))
                        .foregroundStyle(isRoot ? Theme.teal : Theme.frost.opacity(0.45))
                        .frame(width: 40, alignment: .leading)
                    ForEach(0..<transport.stepCount, id: \.self) { step in
                        Cell(on: melody[step] == row, color: Theme.cyan,
                             playhead: step == transport.currentStep, beat: step % 4 == 0, rootRow: isRoot,
                             ghost: others.contains { $0[step] == row })
                            .onTapGesture { transport.toggleMelody(row: row, step: step) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Drums editor (all drum layers)

private struct DrumsEditor: View {
    @ObservedObject var transport: TransportController

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(transport.drumTracks) { t in
                        HStack(spacing: 4) {
                            Menu {
                                ForEach(DrumSound.allCases) { d in Button(d.name) { transport.setTrackSound(t.id, sound: d.rawValue) } }
                                Divider()
                                Button(role: .destructive) { transport.removeTrack(t.id) } label: { Label("Remove", systemImage: "trash") }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(t.displayName).font(Theme.body(12)).lineLimit(1)
                                    Image(systemName: "chevron.down").font(.system(size: 8))
                                }
                                .foregroundStyle(t.muted ? Theme.frost.opacity(0.4) : Theme.frost.opacity(0.8))
                                .frame(width: 64, alignment: .leading)
                            }
                            Button { transport.toggleMute(t.id) } label: {
                                Image(systemName: t.muted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                                    .font(.system(size: 11)).foregroundStyle(t.muted ? .red.opacity(0.8) : Theme.frost.opacity(0.6))
                                    .frame(width: 22)
                            }
                            ForEach(0..<transport.stepCount, id: \.self) { step in
                                Cell(on: t.drumSteps[step], color: Theme.teal,
                                     playhead: step == transport.currentStep, beat: step % 4 == 0, rootRow: false)
                                    .frame(height: 30)
                                    .onTapGesture { transport.toggleDrum(t.id, step: step) }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Menu {
                ForEach(DrumSound.allCases) { d in Button(d.name) { transport.addDrumLayer(d) } }
            } label: {
                Label("Add drum", systemImage: "plus").font(Theme.body(13)).foregroundStyle(Theme.teal)
            }
        }
    }
}

// MARK: - Shared cell

struct Cell: View {
    let on: Bool
    let color: Color
    let playhead: Bool
    let beat: Bool
    let rootRow: Bool
    var ghost: Bool = false   // a note from another layer occupies this cell

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ghost && !on ? color.opacity(0.5) : .clear, lineWidth: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(playhead ? Theme.frost.opacity(0.9) : .clear, lineWidth: 1.5))
            .frame(maxWidth: .infinity).frame(height: 22)
            .shadow(color: on ? color.opacity(playhead ? 0.9 : 0.4) : .clear, radius: 5)
    }
    private var fill: Color {
        if on { return color.opacity(playhead ? 1.0 : 0.85) }
        if ghost { return color.opacity(0.20) }   // faint shadow of another layer's note
        let base = beat ? 0.10 : 0.05
        return Color.white.opacity(rootRow ? base + 0.05 : base)
    }
}

// MARK: - Transport bar

private struct TransportBar: View {
    @ObservedObject var transport: TransportController

    var body: some View {
        HStack(spacing: 18) {
            Button(action: transport.togglePlay) {
                Image(systemName: transport.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.bgTop)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Theme.teal))
                    .shadow(color: Theme.teal.opacity(transport.isPlaying ? 0.7 : 0.3), radius: 12)
            }
            Spacer()
            HStack(spacing: 12) {
                tempoButton("minus", delta: -1)
                VStack(spacing: 0) {
                    Text("\(Int(transport.tempo))").font(Theme.display(26)).foregroundStyle(Theme.frost).monospacedDigit()
                    Text("BPM").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5)).tracking(2)
                }
                .frame(width: 60)
                tempoButton("plus", delta: 1)
            }
        }
        .padding(.vertical, 11).padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.frost.opacity(0.12), lineWidth: 1)))
    }
    private func tempoButton(_ symbol: String, delta: Double) -> some View {
        Button { transport.setTempo(transport.tempo + delta) } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.frost)
                .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.08)))
        }
    }
}

#Preview { PatternStudioView() }
