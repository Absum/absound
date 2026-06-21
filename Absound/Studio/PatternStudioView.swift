//
//  PatternStudioView.swift
//  M1 Studio surface: a transport bar over a live 16-step grid that scrolls with
//  the audio clock. The grid is read-only here; M2 makes it editable and adds the
//  scale-locked melody editor.
//

import SwiftUI

struct PatternStudioView: View {
    @StateObject private var transport = TransportController()

    private let trackColors: [Color] = [Theme.cyan, Theme.teal, Theme.steel, Theme.frost]

    var body: some View {
        ZStack {
            ArcticBackground(glow: transport.isPlaying)
            VStack(spacing: 22) {
                header
                StepGridView(grid: transport.grid,
                             labels: transport.trackLabels,
                             colors: trackColors,
                             currentStep: transport.currentStep)
                TransportBar(transport: transport)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
        .onAppear {
            transport.onAppear()
            #if DEBUG
            if ProcessInfo.processInfo.environment["ABSOUND_AUTOPLAY"] != nil { transport.play() }
            #endif
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ABSOUND")
                .font(Theme.display(26))
                .foregroundStyle(Theme.frost)
                .tracking(4)
            Spacer()
            Text("C minor")
                .font(Theme.title(16))
                .foregroundStyle(Theme.teal)
                .tracking(1)
        }
    }
}

/// Read-only step grid with a moving playhead column.
private struct StepGridView: View {
    let grid: [[Bool]]
    let labels: [String]
    let colors: [Color]
    let currentStep: Int

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(grid.enumerated()), id: \.offset) { trackIdx, row in
                HStack(spacing: 6) {
                    Text(labels[safe: trackIdx] ?? "")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.frost.opacity(0.7))
                        .frame(width: 48, alignment: .leading)
                    ForEach(row.indices, id: \.self) { step in
                        cell(on: row[step],
                             color: colors[safe: trackIdx] ?? Theme.teal,
                             active: step == currentStep,
                             beat: step % 4 == 0)
                    }
                }
            }
        }
    }

    private func cell(on: Bool, color: Color, active: Bool, beat: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(on ? color.opacity(active ? 1.0 : 0.85) : Color.white.opacity(beat ? 0.10 : 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(active ? Theme.frost.opacity(0.9) : .clear, lineWidth: 1.5)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .shadow(color: on && active ? color.opacity(0.8) : .clear, radius: 6)
    }
}

private struct TransportBar: View {
    @ObservedObject var transport: TransportController

    var body: some View {
        HStack(spacing: 22) {
            Button(action: transport.togglePlay) {
                Image(systemName: transport.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.bgTop)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.teal))
                    .shadow(color: Theme.teal.opacity(transport.isPlaying ? 0.7 : 0.3), radius: 12)
            }

            Spacer()

            HStack(spacing: 14) {
                tempoButton("minus", delta: -1)
                VStack(spacing: 0) {
                    Text("\(Int(transport.tempo))")
                        .font(Theme.display(30))
                        .foregroundStyle(Theme.frost)
                        .monospacedDigit()
                    Text("BPM")
                        .font(Theme.light(12))
                        .foregroundStyle(Theme.frost.opacity(0.5))
                        .tracking(2)
                }
                .frame(width: 70)
                tempoButton("plus", delta: 1)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.frost.opacity(0.12), lineWidth: 1))
        )
    }

    private func tempoButton(_ symbol: String, delta: Double) -> some View {
        Button { transport.setTempo(transport.tempo + delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.frost)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    PatternStudioView()
}
