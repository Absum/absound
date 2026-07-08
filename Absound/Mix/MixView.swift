//
//  MixView.swift
//  The mixer: one channel strip per layer (gain, pan, mute/solo, sends, FX
//  chain) plus the MASTER strip with the master-bus insert chain. Synth strips
//  write through to the layer's patch (so mix moves save with the sound);
//  drum strips edit the layer's StripValues.
//

import SwiftUI

/// Horizontal dB-mapped peak meter: green → yellow (−6 dB) → red (over 0 dBFS).
/// `level` is linear post-fader peak; > 1.0 means overdriving into the limiter.
struct MeterBar: View {
    let level: Float
    var height: CGFloat = 6

    /// Map linear level to 0..1 across a −40 dB…+6 dB window.
    private var norm: CGFloat {
        guard level > 0.0001 else { return 0 }
        let db = 20 * log10(Double(level))
        return CGFloat(min(max((db + 40) / 46, 0), 1))
    }
    private var zeroDbNorm: CGFloat { 40.0 / 46.0 }
    private var clipping: Bool { level > 1.0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2).fill(Color.black.opacity(0.35))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(LinearGradient(
                        stops: [
                            .init(color: Theme.teal, location: 0),
                            .init(color: Theme.teal, location: 0.6),
                            .init(color: .yellow, location: zeroDbNorm - 0.08),
                            .init(color: .red, location: zeroDbNorm),
                            .init(color: .red, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * norm, 0))
                    .animation(.linear(duration: 0.05), value: norm)
                // 0 dBFS tick.
                Rectangle().fill(Theme.frost.opacity(0.5))
                    .frame(width: 1)
                    .offset(x: geo.size.width * zeroDbNorm)
                // Clip lamp.
                if clipping {
                    HStack {
                        Spacer()
                        Circle().fill(Color.red).frame(width: height, height: height)
                            .shadow(color: .red, radius: 3)
                    }
                }
            }
        }
        .frame(height: height)
    }
}

struct MixView: View {
    @ObservedObject var transport: TransportController

    @State private var chainLayer: Layer?       // per-sound chain sheet target
    @State private var showMasterChain = false

    var body: some View {
        ZStack {
            ArcticBackground(glow: transport.isPlaying)
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text("MIX").font(Theme.display(24)).foregroundStyle(Theme.frost).tracking(4)
                        Spacer()
                        Button(action: transport.togglePlay) {
                            Image(systemName: transport.isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.bgTop)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Theme.teal))
                        }
                    }
                    masterStrip
                    ForEach(transport.project.layers) { layer in
                        strip(layer)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 16)
            }
        }
        .sheet(item: $chainLayer) { layer in
            chainSheet(title: layer.displayName,
                       chain: bindingForLayerChain(layer.id))
        }
        .sheet(isPresented: $showMasterChain) {
            chainSheet(title: "Master",
                       chain: Binding(get: { transport.masterChain }, set: { transport.masterChain = $0 }))
        }
        .onAppear { transport.onAppear(); transport.metersEnabled = true }
        .onDisappear { transport.metersEnabled = false }
    }

    // MARK: - Strips

    private var masterStrip: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill").font(.system(size: 13)).foregroundStyle(Theme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MASTER").font(Theme.title(15)).foregroundStyle(Theme.frost).tracking(1)
                    FXChainSummary(chain: transport.masterChain)
                }
                Spacer()
                Button { showMasterChain = true } label: { fxButton }
            }
            MeterBar(level: transport.masterLevel, height: 10)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.teal.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.teal.opacity(0.35), lineWidth: 1))
    }

    private func strip(_ layer: Layer) -> some View {
        let isSynth = layer.kind == .synth
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isSynth ? "waveform" : "circle.grid.2x1.fill")
                    .font(.system(size: 11)).foregroundStyle(isSynth ? Theme.cyan : Theme.steel)
                Text(layer.displayName).font(Theme.body(15))
                    .foregroundStyle(layer.muted ? Theme.frost.opacity(0.4) : Theme.frost)
                if isSynth { FXChainSummary(chain: layer.patch?.fxChain ?? []) }
                Spacer()
                mixButton(layer.muted ? "M" : "M", active: layer.muted, color: .red) { transport.toggleMute(layer.id) }
                mixButton("S", active: layer.soloed, color: Theme.teal) { transport.toggleSolo(layer.id) }
                if isSynth {
                    Button { chainLayer = layer } label: { fxButton }
                }
            }
            HStack(spacing: 10) {
                knob("Gain", get: { gain(layer) }, set: { setGain(layer, $0) }, range: 0...1.5)
                knob("Pan", get: { pan(layer) }, set: { setPan(layer, $0) }, range: -1...1)
                knob("Delay", get: { dSend(layer) }, set: { setDSend(layer, $0) }, range: 0...1)
                knob("Reverb", get: { rSend(layer) }, set: { setRSend(layer, $0) }, range: 0...1)
            }
            MeterBar(level: transport.meterLevels[layer.id] ?? 0, height: 6)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.frost.opacity(0.10), lineWidth: 1))
    }

    private var fxButton: some View {
        HStack(spacing: 3) {
            Image(systemName: "fx").font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(Theme.cyan)
        .frame(width: 36, height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }

    private func mixButton(_ label: String, active: Bool, color: Color, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label).font(Theme.title(13))
                .foregroundStyle(active ? Theme.bgTop : Theme.frost.opacity(0.6))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? color.opacity(0.85) : Color.white.opacity(0.08)))
        }
    }

    private func knob(_ label: String, get: @escaping () -> Float, set: @escaping (Float) -> Void,
                      range: ClosedRange<Float>) -> some View {
        ArcticKnob(label, value: Binding(get: get, set: set), range: range)
    }

    private func chainSheet(title: String, chain: Binding<[FXSlot]>) -> some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    FXChainView(chain: chain).padding(14)
                }
            }
            .navigationTitle("\(title) — Effects")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    // MARK: - Strip value plumbing (synth -> patch, drum -> StripValues)

    private func bindingForLayerChain(_ id: UUID) -> Binding<[FXSlot]> {
        Binding(
            get: { transport.project.layers.first { $0.id == id }?.patch?.fxChain ?? [] },
            set: { newChain in
                guard var p = transport.project.layers.first(where: { $0.id == id })?.patch else { return }
                p.fxChain = newChain
                transport.applyPatch(id, patch: p)
            }
        )
    }

    private func updatePatch(_ layer: Layer, _ mutate: (inout SynthPatch) -> Void) {
        guard var p = layer.patch else { return }
        mutate(&p)
        transport.applyPatch(layer.id, patch: p)
    }
    private func updateStrip(_ layer: Layer, _ mutate: (inout StripValues) -> Void) {
        var s = transport.drumStrip(layer.id)
        mutate(&s)
        transport.setDrumStrip(layer.id, s)
    }

    private func gain(_ l: Layer) -> Float { l.kind == .synth ? (l.patch?.gain ?? 0.85) : transport.drumStrip(l.id).gain }
    private func pan(_ l: Layer) -> Float { l.kind == .synth ? (l.patch?.pan ?? 0) : transport.drumStrip(l.id).pan }
    private func dSend(_ l: Layer) -> Float { l.kind == .synth ? (l.patch?.delaySend ?? 0) : transport.drumStrip(l.id).delaySend }
    private func rSend(_ l: Layer) -> Float { l.kind == .synth ? (l.patch?.reverbSend ?? 0) : transport.drumStrip(l.id).reverbSend }

    private func setGain(_ l: Layer, _ v: Float) {
        l.kind == .synth ? updatePatch(l) { $0.gain = v } : updateStrip(l) { $0.gain = v }
    }
    private func setPan(_ l: Layer, _ v: Float) {
        l.kind == .synth ? updatePatch(l) { $0.pan = v } : updateStrip(l) { $0.pan = v }
    }
    private func setDSend(_ l: Layer, _ v: Float) {
        l.kind == .synth ? updatePatch(l) { $0.delaySend = v } : updateStrip(l) { $0.delaySend = v }
    }
    private func setRSend(_ l: Layer, _ v: Float) {
        l.kind == .synth ? updatePatch(l) { $0.reverbSend = v } : updateStrip(l) { $0.reverbSend = v }
    }
}
