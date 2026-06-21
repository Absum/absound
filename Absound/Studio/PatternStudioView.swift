//
//  PatternStudioView.swift
//  M2 Studio: an editable, scale-locked pattern composer.
//
//  Key/scale + synth preset pickers up top; a segmented Melody|Drums switch
//  selects the editor. The melody piano-roll is scale-locked (every row is an
//  in-key pitch), the drum grid toggles hits. Everything auditions live through
//  the M1 engine, and a shared playhead column tracks the audio clock.
//

import SwiftUI

struct PatternStudioView: View {
    @StateObject private var transport = TransportController()
    @State private var editor: EditorTab = .melody

    enum EditorTab: String, CaseIterable { case melody = "Melody", drums = "Drums" }

    var body: some View {
        ZStack {
            ArcticBackground(glow: transport.isPlaying)
            VStack(spacing: 12) {
                header
                pickers
                Picker("", selection: $editor) {
                    ForEach(EditorTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Group {
                    switch editor {
                    case .melody:
                        ScrollView { MelodyRoll(transport: transport) }
                    case .drums:
                        DrumGrid(transport: transport)
                    }
                }
                .frame(maxHeight: .infinity)

                TransportBar(transport: transport)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .onAppear {
            transport.onAppear()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["ABSOUND_TAB"] == "drums" { editor = .drums }
            if env["ABSOUND_AUTOPLAY"] != nil { transport.play() }
            #endif
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ABSOUND").font(Theme.display(24)).foregroundStyle(Theme.frost).tracking(4)
            Spacer()
            Button { transport.clear() } label: {
                Image(systemName: "trash").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.frost.opacity(0.7))
            }
        }
    }

    private var pickers: some View {
        HStack(spacing: 8) {
            menu(label: transport.context.rootName, systemImage: "key") {
                ForEach(0..<12, id: \.self) { r in
                    Button(MusicalContext.rootNames[r]) { transport.setRoot(r) }
                }
            }
            menu(label: transport.context.scale.displayName, systemImage: "music.note.list") {
                ForEach(Scale.allCases) { s in
                    Button(s.displayName) { transport.setScale(s) }
                }
            }
            menu(label: transport.preset.name, systemImage: "waveform") {
                ForEach(SynthPreset.allCases) { p in
                    Button(p.name) { transport.setPreset(p) }
                }
            }
        }
    }

    private func menu<Content: View>(label: String, systemImage: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11))
                Text(label).font(Theme.body(15)).lineLimit(1)
            }
            .foregroundStyle(Theme.frost)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.frost.opacity(0.12), lineWidth: 1))
        }
    }
}

// MARK: - Melody piano-roll (scale-locked)

private struct MelodyRoll: View {
    @ObservedObject var transport: TransportController

    var body: some View {
        let ctx = transport.context
        let rows = Array((0..<transport.melodyRowCount).reversed()) // high pitch on top
        VStack(spacing: 3) {
            ForEach(rows, id: \.self) { row in
                let isRoot = (ctx.midiNote(forRow: row) - ctx.root) % 12 == 0
                HStack(spacing: 3) {
                    Text(ctx.noteName(forRow: row))
                        .font(Theme.light(11))
                        .foregroundStyle(isRoot ? Theme.teal : Theme.frost.opacity(0.45))
                        .frame(width: 40, alignment: .leading)
                    ForEach(0..<transport.stepCount, id: \.self) { step in
                        Cell(on: transport.pattern.melody[step] == row,
                             color: Theme.cyan,
                             playhead: step == transport.currentStep,
                             beat: step % 4 == 0,
                             rootRow: isRoot)
                            .onTapGesture { transport.toggleMelody(row: row, step: step) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Drum grid

private struct DrumGrid: View {
    @ObservedObject var transport: TransportController
    private let colors: [Color] = [Theme.teal, Theme.steel, Theme.frost]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(DrumLane.allCases) { lane in
                HStack(spacing: 4) {
                    Text(lane.label)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.frost.opacity(0.7))
                        .frame(width: 46, alignment: .leading)
                    ForEach(0..<transport.stepCount, id: \.self) { step in
                        Cell(on: transport.pattern.drums[lane.rawValue][step],
                             color: colors[lane.rawValue],
                             playhead: step == transport.currentStep,
                             beat: step % 4 == 0,
                             rootRow: false)
                            .frame(height: 34)
                            .onTapGesture { transport.toggleDrum(lane, step: step) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

// MARK: - Shared cell

private struct Cell: View {
    let on: Bool
    let color: Color
    let playhead: Bool
    let beat: Bool
    let rootRow: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(playhead ? Theme.frost.opacity(0.9) : .clear, lineWidth: 1.5)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .shadow(color: on ? color.opacity(playhead ? 0.9 : 0.4) : .clear, radius: 5)
    }

    private var fill: Color {
        if on { return color.opacity(playhead ? 1.0 : 0.85) }
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
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.bgTop)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Theme.teal))
                    .shadow(color: Theme.teal.opacity(transport.isPlaying ? 0.7 : 0.3), radius: 12)
            }
            Spacer()
            HStack(spacing: 12) {
                tempoButton("minus", delta: -1)
                VStack(spacing: 0) {
                    Text("\(Int(transport.tempo))").font(Theme.display(28))
                        .foregroundStyle(Theme.frost).monospacedDigit()
                    Text("BPM").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5)).tracking(2)
                }
                .frame(width: 64)
                tempoButton("plus", delta: 1)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.frost.opacity(0.12), lineWidth: 1))
        )
    }

    private func tempoButton(_ symbol: String, delta: Double) -> some View {
        Button { transport.setTempo(transport.tempo + delta) } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.frost)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
    }
}

#Preview {
    PatternStudioView()
}
