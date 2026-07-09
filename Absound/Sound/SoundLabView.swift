//
//  SoundLabView.swift
//  The synth editor. Simple view = 6 macro sliders; Advanced = every ABPatch
//  parameter. Live param-driven visualizations (waveform, filter curve, ADSR,
//  LFO) make the patch visible as well as audible.
//
//  Two modes:
//  - Layer mode (from the Studio): edits the selected layer's patch in place.
//  - Standalone (from the Sounds tab): edits a draft against the engine's
//    dedicated preview track — no layer needed; Save lands in My Sounds.
//

import SwiftUI

struct SoundLabView: View {
    @ObservedObject var transport: TransportController
    @EnvironmentObject var library: PatchLibrary
    @EnvironmentObject var toast: ToastCenter
    @Environment(\.dismiss) private var dismiss

    let standalone: Bool
    @State private var draft: SynthPatch
    @State private var mode: Mode = .simple
    @State private var original: SynthPatch?
    @State private var showRename = false
    @State private var showSaveAs = false
    @State private var confirmRevert = false
    @State private var newName = ""
    @State private var saveAsName = ""

    enum Mode: String, CaseIterable { case simple = "Simple", advanced = "Advanced" }

    init(transport: TransportController, standalone: Bool = false, initialPatch: SynthPatch? = nil) {
        self.transport = transport
        self.standalone = standalone
        self._draft = State(initialValue: initialPatch ?? PatchFactory.presets[0])
    }

    private var patch: Binding<SynthPatch> {
        if standalone {
            return Binding(
                get: { draft },
                set: { draft = $0; transport.applyPreviewPatch($0) }
            )
        }
        return Binding(
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
                                simpleHeaderViz
                                MacroPanel(patch: patch)
                                LabSection(title: "EFFECTS") {
                                    FXChainSummary(chain: current.fxChain)
                                    Text("Edit the chain in Advanced")
                                        .font(Theme.light(10)).foregroundStyle(Theme.frost.opacity(0.3))
                                }
                            } else {
                                oscSection
                                filterSection
                                envSection
                                modSection
                                fxSection
                                outSection
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    AuditionPads(transport: transport) { row in
                        standalone ? transport.auditionPreview(row: row) : transport.audition(row: row)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { saveAsName = "\(current.name) 2"; showSaveAs = true } label: {
                            Label("Save as…", systemImage: "square.and.arrow.down.on.square")
                        }
                        Button { newName = current.name; showRename = true } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmRevert = true } label: { Label("Revert changes", systemImage: "arrow.uturn.backward") }
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
            .confirmationDialog("Discard all changes since opening this sound?",
                                isPresented: $confirmRevert, titleVisibility: .visible) {
                Button("Revert changes", role: .destructive) { revert() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename sound", isPresented: $showRename) {
                TextField("Name", text: $newName)
                Button("Rename") { rename() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Save as new sound", isPresented: $showSaveAs) {
                TextField("Name", text: $saveAsName)
                Button("Save") { saveAs() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current sound keeps its saved state; your edits become a new sound in My Sounds.")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if standalone { transport.applyPreviewPatch(draft) }
            if original == nil { original = current }
        }
    }

    /// Waveform + filter response side by side — the sound at a glance.
    private var simpleHeaderViz: some View {
        VStack(spacing: 8) {
            WaveShapeView(patch: current, height: 76)
            FilterCurveView(patch: current, height: 56)
        }
    }

    // MARK: - Save / revert / rename

    private func save() {
        if standalone {
            if isSavedUserPatch {
                library.save(draft)
                toast.show("Sound changes saved")
            } else {
                draft = library.saveAsCopy(of: draft)   // keep editing the saved copy
                toast.show("Saved to My Sounds as \"\(draft.name)\"")
            }
            original = draft
        } else {
            guard let layerId = transport.selectedLayerId else { return }
            if isSavedUserPatch {
                library.save(current)
                toast.show("Sound changes saved")
            } else {
                let copy = library.saveAsCopy(of: current)
                transport.applyPatch(layerId, patch: copy)
                toast.show("Saved to My Sounds as \"\(copy.name)\"")
            }
            original = transport.selectedPatch
        }
    }

    /// Branch the current edits into a NEW My Sound under a chosen name; the
    /// lab (and layer, in layer mode) switches to the new copy, leaving the
    /// original sound's saved state untouched.
    private func saveAs() {
        let copy = library.saveAsCopy(of: current, named: saveAsName)
        if standalone {
            draft = copy
            transport.applyPreviewPatch(copy)
        } else if let layerId = transport.selectedLayerId {
            transport.applyPatch(layerId, patch: copy)
        }
        original = copy
        toast.show("Saved as \"\(copy.name)\"")
    }

    private func revert() {
        guard let o = original else { return }
        if standalone {
            draft = o
            transport.applyPreviewPatch(o)
        } else if let layerId = transport.selectedLayerId {
            transport.applyPatch(layerId, patch: o)
        }
        toast.show("Changes reverted", icon: "arrow.uturn.backward.circle.fill")
    }

    private func rename() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var p = current
        p.name = trimmed
        patch.wrappedValue = p
        if isSavedUserPatch { library.rename(p.id, to: trimmed) }
        toast.show("Renamed to \"\(trimmed)\"", icon: "pencil.circle.fill")
    }

    // MARK: - Advanced sections

    private var oscSection: some View {
        LabSection(title: "OSCILLATORS") {
            WaveShapeView(patch: current)
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
            FilterCurveView(patch: current)
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
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    Text("Amp").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5))
                    ADSRShapeView(a: current.ampA, d: current.ampD, s: current.ampS, r: current.ampR, color: Theme.cyan)
                }
                VStack(spacing: 4) {
                    Text("Filter / Mod").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5))
                    ADSRShapeView(a: current.modA, d: current.modD, s: current.modS, r: current.modR, color: Theme.steel)
                }
            }
            HStack(spacing: 10) {
                ArcticKnob("A", value: patch.ampA, range: 0.001...1.5, curve: .log, format: "%.2fs")
                ArcticKnob("D", value: patch.ampD, range: 0.01...1.5, curve: .log, format: "%.2fs")
                ArcticKnob("S", value: patch.ampS, range: 0...1)
                ArcticKnob("R", value: patch.ampR, range: 0.01...2, curve: .log, format: "%.2fs")
            }
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
            LFOShapeView(patch: current)
            segmented(["Off", "Pitch", "Filter", "Volume", "Pan"], value: patch.lfoTarget)
            segmented(["Sine", "Tri", "S&H"], value: patch.lfoShape)
            HStack(spacing: 10) {
                ArcticKnob("Rate", value: patch.lfoRateHz, range: 0.05...20, curve: .log, format: "%.1fHz")
                ArcticKnob("Depth", value: patch.lfoDepth, range: 0...1)
                ArcticKnob("Glide", value: patch.glide, range: 0...0.5, format: "%.2fs")
                ArcticKnob("Vel", value: patch.velAmount, range: 0...1)
            }
        }
    }

    private var fxSection: some View {
        LabSection(title: "EFFECTS") {
            FXChainView(chain: Binding(
                get: { patch.wrappedValue.fxChain },
                set: { var p = patch.wrappedValue; p.fxChain = $0; patch.wrappedValue = p }
            ))
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

struct AuditionPads: View {
    @ObservedObject var transport: TransportController
    var action: (Int) -> Void

    var body: some View {
        let ctx = transport.context
        let n = ctx.scale.degreeCount
        HStack(spacing: 4) {
            ForEach(0...n, id: \.self) { deg in
                let row = n + deg   // middle octave of the editor range
                let isRoot = deg == 0 || deg == n
                Button { action(row) } label: {
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
