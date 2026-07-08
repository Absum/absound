//
//  ArcticKnob.swift
//  The Sound Lab's rotary control: an arc-indicator knob adjusted by vertical
//  drag, with label above and live value readout below. Arctic-styled.
//

import SwiftUI

struct ArcticKnob: View {
    enum Curve { case linear, log }

    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var step: Float = 0
    var curve: Curve = .linear
    var format: String = "%.2f"

    @State private var dragStartNorm: Float?

    init(_ label: String, value: Binding<Float>, range: ClosedRange<Float>,
         step: Float = 0, curve: Curve = .linear, format: String = "%.2f") {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.curve = curve
        self.format = format
    }

    private var norm: Float {
        switch curve {
        case .linear:
            return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        case .log:
            let lo = log(Double(max(range.lowerBound, 1e-5))), hi = log(Double(range.upperBound))
            return Float((log(Double(max(value, 1e-5))) - lo) / (hi - lo))
        }
    }

    private func denorm(_ n: Float) -> Float {
        let c = min(max(n, 0), 1)
        var v: Float
        switch curve {
        case .linear:
            v = range.lowerBound + c * (range.upperBound - range.lowerBound)
        case .log:
            let lo = log(Double(max(range.lowerBound, 1e-5))), hi = log(Double(range.upperBound))
            v = Float(exp(lo + Double(c) * (hi - lo)))
        }
        if step > 0 { v = (v / step).rounded() * step }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(Theme.light(10)).foregroundStyle(Theme.frost.opacity(0.55)).lineLimit(1)
            ZStack {
                // Track arc (270°, gap at the bottom).
                Circle()
                    .trim(from: 0.125, to: 0.875)
                    .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(90))
                // Value arc.
                Circle()
                    .trim(from: 0.125, to: 0.125 + 0.75 * CGFloat(norm))
                    .stroke(Theme.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .shadow(color: Theme.teal.opacity(0.5), radius: 3)
                // Pointer dot.
                Circle()
                    .fill(Theme.frost)
                    .frame(width: 5, height: 5)
                    .offset(y: -14)
                    .rotationEffect(.degrees(Double(norm) * 270 - 135))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStartNorm == nil { dragStartNorm = norm }
                        let delta = Float(-g.translation.height / 150)   // full range ≈ 150pt
                        value = denorm((dragStartNorm ?? norm) + delta)
                    }
                    .onEnded { _ in dragStartNorm = nil }
            )
            Text(String(format: format, value))
                .font(Theme.light(9)).foregroundStyle(Theme.frost.opacity(0.45))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
