//
//  SoundLabView.swift
//  The synth editor. Simple view = 6 macro sliders for fast shaping; Advanced
//  view = every ABPatch parameter in Arctic-styled sections. An in-key audition
//  pad strip keeps each tweak audible. Edits apply live to the selected layer's
//  patch; Save puts the sound into My Sounds (persisted), Revert restores the
//  patch as it was when the Lab opened.
//

import SwiftUI

struct SoundLabView: View {
    @ObservedObject var transport: TransportController
    @EnvironmentObject var library: PatchLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .simple
    @State private var original: SynthPatch?
    @State private var showRename = false
    @State private var newName = ""

    enum Mode: String, CaseIterable { case simple = "Simple", advanced = "Advanced" }

    private var patch: Binding<SynthPatch> {
        Binding(
            get: { transport.selectedPatch ?? PatchFactory.presets[0] },
            set: { newValue in
                if let id = transport.selectedLayerId { transport.applyPatch(id, patch: newValue) }
            }
        )
    }
    private var current: SynthPatch { patch.wrappedValue }
    private var isSavedUserPatch: Bool { library.contains(current.id) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14).padding(.top, 6)

                    ScrollView {
                        VStack(spacing: 16) {
                            if mode == .simple {
                                MacroPanel(patch: patch)
                            } else {
                                oscSection
                                filterSection
                                envSection
                                modSection
                                outSection
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    AuditionPads(transport: transport)
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { newName = current.name; showRename = true } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button { revert() } label: { Label("Revert changes", systemImage: "arrow.uturn.backward") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSavedUserPatch ? "Save" : "Save to My Sounds") { save() }
                        .font(Theme.body(15))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename sound", isPresented: $showRename) {
                TextField("Name", text: $newName)
                Button("Rename") { rename() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if original == nil { original = transport.selectedPatch } }
    }

    // MARK: - Save / revert / rename

    private func save() {
        guard let layerId = transport.selectedLayerId else { return }
        if isSavedUserPatch {
            library.save(current)                       // update in place
        } else {
            let copy = library.saveAsCopy(of: current)  // factory (or unsaved) -> new My Sound
            transport.applyPatch(layerId, patch: copy)  // layer now tracks the saved copy
        }
        original = transport.selectedPatch
    }

    private func revert() {
        guard let layerId = transport.selectedLayerId, let o = original else { return }
        transport.applyPatch(layerId, patch: o)
    }

    private func rename() {
        guard let layerId = transport.selectedLayerId else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var p = current
        p.name = trimmed
        transport.applyPatch(layerId, patch: p)
        if isSavedUserPatch { library.rename(p.id, to: trimmed) }
    }

    // MARK: - Advanced sections

    private var oscSection: some View {
        LabSection(title: "OSCILLATORS") {
            wavePicker("Osc 1", value: patch.osc1Wave)
            HStack(spacing: 10) {
                ArcticKnob("Mix", value: patch.oscMix, range: 0...1)
                ArcticKnob("Semi", value: intKnob(patch.osc2Semi), range: -24...24, step: 1, format: "%.0f")
                ArcticKnob("Sub", value: patch.subLevel, range: 0...1)
                ArcticKnob("Noise", value: patch.noiseLevel, range: 0...1)
            }
            wavePicker("Osc 2", value: patch.osc2Wave)
            HStack(spacing: 10) {
                ArcticKnob("Unison", value: intKnob(patch.unison), range: 1...7, step: 1, format: "%.0f")
                ArcticKnob("Detune", value: patch.unisonDetune, range: 0...50, format: "%.0f¢")
                ArcticKnob("Width", value: patch.unisonWidth, range: 0...1)
                Spacer(minLength: 0).frame(maxWidth: .infinity)
            }
        }
    }

    private var filterSection: some View {
        LabSection(title: "FILTER") {
            segmented(["LP", "BP", "HP"], value: patch.filterType)
            HStack(spacing: 10) {
                ArcticKnob("Cutoff", value: patch.cutoff, range: 40...12000, curve: .log, format: "%.0f")
                ArcticKnob("Reso", value: patch.resonance, range: 0...1)
                ArcticKnob("Drive", value: patch.drive, range: 0...1)
                ArcticKnob("Env", value: patch.envAmount, range: -1...1)
            }
        }
    }

    private var envSection: some View {
        LabSection(title: "ENVELOPES") {
            Text("Amp").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5))
            HStack(spacing: 10) {
                ArcticKnob("A", value: patch.ampA, range: 0.001...1.5, curve: .log, format: "%.2fs")
                ArcticKnob("D", value: patch.ampD, range: 0.01...1.5, curve: .log, format: "%.2fs")
                ArcticKnob("S", value: patch.ampS, range: 0...1)
                ArcticKnob("R", value: patch.ampR, range: 0.01...2, curve: .log, format: "%.2fs")
            }
            Text("Filter / Mod").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5))
            HStack(spacing: 10) {
                ArcticKnob("A", value: patch.modA, range: 0.001...1.5, curve: .log, format: "%.2fs")
                ArcticKnob("D", value: patch.modD, range: 0.01...1.5, curve: .log, format: "%.2fs")
                ArcticKnob("S", value: patch.modS, range: 0...1)
                ArcticKnob("R", value: patch.modR, range: 0.01...2, curve: .log, format: "%.2fs")
            }
        }
    }

    private var modSection: some View {
        LabSection(title: "MOTION") {
            segmented(["Off", "Pitch", "Filter", "Volume", "Pan"], value: patch.lfoTarget)
            HStack(spacing: 10) {
                ArcticKnob("Rate", value: patch.lfoRateHz, range: 0.05...20, curve: .log, format: "%.1fHz")
                ArcticKnob("Depth", value: patch.lfoDepth, range: 0...1)
                ArcticKnob("Glide", value: patch.glide, range: 0...0.5, format: "%.2fs")
                ArcticKnob("Vel", value: patch.velAmount, range: 0...1)
            }
        }
    }

    private var outSection: some View {
        LabSection(title: "OUTPUT") {
            HStack(spacing: 10) {
                ArcticKnob("Gain", value: patch.gain, range: 0...1.5)
                ArcticKnob("Pan", value: patch.pan, range: -1...1)
                ArcticKnob("Delay", value: patch.delaySend, range: 0...1)
                ArcticKnob("Reverb", value: patch.reverbSend, range: 0...1)
            }
        }
    }

    // MARK: - Helpers

    private func intKnob(_ b: Binding<Int>) -> Binding<Float> {
        Binding(get: { Float(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) })
    }

    private func wavePicker(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5)).frame(width: 42, alignment: .leading)
            Picker("", selection: value) {
                Text("Saw").tag(0); Text("Square").tag(1); Text("Tri").tag(2); Text("Sine").tag(3)
            }
            .pickerStyle(.segmented)
        }
    }

    private func segmented(_ labels: [String], value: Binding<Int>) -> some View {
        Picker("", selection: value) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, l in Text(l).tag(i) }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Simple macros

/// Six macro sliders that write through to the underlying patch fields.
/// Inverse mappings are approximate — good enough to reflect the patch state.
private struct MacroPanel: View {
    @Binding var patch: SynthPatch

    var body: some View {
        LabSection(title: "SHAPE YOUR SOUND") {
            macro("Brightness", icon: "sun.max.fill",
                  get: { p in
                      let lo = log(200.0), hi = log(8000.0)
                      return Float((log(Double(max(p.cutoff, 200))) - lo) / (hi - lo)).clamped01
                  },
                  set: { p, v in
                      p.cutoff = Float(exp(log(200.0) + Double(v) * (log(8000.0) - log(200.0))))
                      p.envAmount = 0.2 + 0.5 * v
                  })
            macro("Warmth", icon: "flame.fill",
                  get: { ($0.drive / 0.7).clamped01 },
                  set: { p, v in p.drive = 0.7 * v; p.subLevel = 0.2 + 0.6 * v })
            macro("Width", icon: "arrow.left.and.right",
                  get: { $0.unisonWidth.clamped01 },
                  set: { p, v in
                      p.unisonWidth = v
                      p.unison = 1 + Int((v * 6).rounded())
                      p.unisonDetune = 30 * v
                  })
            macro("Punch", icon: "bolt.fill",
                  get: { (1 - $0.ampS).clamped01 },
                  set: { p, v in
                      p.ampA = max(0.001, 0.25 * (1 - v) * (1 - v))
                      p.ampD = 0.6 - 0.45 * v
                      p.ampS = (1 - v) * 0.9
                  })
            macro("Motion", icon: "waveform.path.ecg",
                  get: { $0.lfoDepth.clamped01 },
                  set: { p, v in
                      p.lfoDepth = v
                      if v > 0.01 && p.lfoTarget == 0 { p.lfoTarget = 2 }   // default: filter motion
                  })
            macro("Space", icon: "sparkles",
                  get: { ($0.reverbSend / 0.6).clamped01 },
                  set: { p, v in p.reverbSend = 0.6 * v; p.delaySend = 0.35 * v })
        }
    }

    private func macro(_ label: String, icon: String,
                       get: @escaping (SynthPatch) -> Float,
                       set: @escaping (inout SynthPatch, Float) -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.cyan).frame(width: 22)
            Text(label).font(Theme.body(14)).foregroundStyle(Theme.frost).frame(width: 86, alignment: .leading)
            Slider(value: Binding(
                get: { get(patch) },
                set: { v in var p = patch; set(&p, v); patch = p }
            ), in: 0...1)
            .tint(Theme.teal)
        }
    }
}

private extension Float {
    var clamped01: Float { Swift.min(Swift.max(self, 0), 1) }
}

// MARK: - Section container

struct LabSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.title(13)).foregroundStyle(Theme.teal).tracking(2)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.frost.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - Audition pads (in-key, root..octave)

private struct AuditionPads: View {
    @ObservedObject var transport: TransportController
    var body: some View {
        let ctx = transport.context
        let n = ctx.scale.degreeCount
        HStack(spacing: 4) {
            ForEach(0...n, id: \.self) { deg in
                let row = n + deg   // middle octave of the editor range
                let isRoot = deg == 0 || deg == n
                Button { transport.audition(row: row) } label: {
                    Text(ctx.noteName(forRow: row))
                        .font(Theme.body(11)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(isRoot ? Theme.bgTop : Theme.frost)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(isRoot ? Theme.teal.opacity(0.85) : Theme.cyan.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
