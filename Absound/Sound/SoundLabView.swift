//
//  SoundLabView.swift
//  The synth editor. Every ABPatch parameter, in Arctic-styled sections, with an
//  in-key audition pad strip so each tweak is heard immediately. Edits apply
//  live to the selected layer's patch (staged race-free in the engine).
//

import SwiftUI

struct SoundLabView: View {
    @ObservedObject var transport: TransportController
    @Environment(\.dismiss) private var dismiss

    private var patch: Binding<SynthPatch> {
        Binding(
            get: { transport.selectedPatch ?? PatchFactory.presets[0] },
            set: { newValue in
                if let id = transport.selectedLayerId { transport.applyPatch(id, patch: newValue) }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            oscSection
                            filterSection
                            envSection
                            modSection
                            outSection
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    AuditionPads(transport: transport)
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
            .navigationTitle(patch.wrappedValue.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

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

    // MARK: Helpers

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

// MARK: - Section container

private struct LabSection<Content: View>: View {
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
