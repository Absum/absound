//
//  SynthViz.swift
//  Param-driven synth visualizations for the Sound Lab: oscillator waveform
//  (with unison ghosts), filter frequency-response curve, ADSR envelope shape,
//  and LFO shape. All computed from the patch, so they track every knob live.
//

import SwiftUI

// MARK: - Naive single-cycle wave shapes (visual only — the engine band-limits)

private func waveSample(_ wave: Int, _ t: Double) -> Double {
    let ph = t - floor(t)
    switch wave {
    case 1: return ph < 0.5 ? 1 : -1                       // square
    case 2: return 4 * abs(ph - 0.5) - 1                   // triangle
    case 3: return sin(ph * 2 * .pi)                       // sine
    default: return 2 * ph - 1                             // saw
    }
}

// MARK: - Oscillator waveform display

struct WaveShapeView: View {
    let patch: SynthPatch
    var height: CGFloat = 72

    var body: some View {
        Canvas { ctx, size in
            let cycles = 2.0
            let midY = size.height / 2
            let amp = size.height * 0.4

            func mixedSample(_ t: Double, detunePhase: Double) -> Double {
                let mix = Double(min(max(patch.oscMix, 0), 1))
                let ratio2 = pow(2.0, Double(patch.osc2Semi) / 12.0)
                var v = (1 - mix) * waveSample(patch.osc1Wave, t + detunePhase)
                v += mix * waveSample(patch.osc2Wave, t * ratio2)
                v += Double(patch.subLevel) * 0.5 * sin((t * 0.5) * 2 * .pi)
                let norm = (1 - mix) + mix + Double(patch.subLevel) * 0.5 + 0.001
                return v / norm
            }

            func trace(detunePhase: Double) -> Path {
                var p = Path()
                let steps = Int(size.width)
                for i in 0...steps {
                    let x = CGFloat(i) / CGFloat(steps)
                    let t = Double(x) * cycles
                    let y = midY - CGFloat(mixedSample(t, detunePhase: detunePhase)) * amp
                    if i == 0 { p.move(to: CGPoint(x: x * size.width, y: y)) }
                    else { p.addLine(to: CGPoint(x: x * size.width, y: y)) }
                }
                return p
            }

            // Center line.
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: midY)); p.addLine(to: CGPoint(x: size.width, y: midY)) },
                       with: .color(.white.opacity(0.06)), lineWidth: 1)

            // Unison ghosts: faint detuned copies fanning out.
            let unison = min(Int(patch.unison), 7)
            if unison > 1 {
                for i in 1..<unison {
                    let offset = Double(i) / Double(unison - 1) * 0.12 * Double(patch.unisonDetune / 50 + 0.2)
                    ctx.stroke(trace(detunePhase: offset),
                               with: .color(Theme.cyan.opacity(0.14)), lineWidth: 1)
                }
            }
            // Main trace with glow.
            let main = trace(detunePhase: 0)
            ctx.stroke(main, with: .color(Theme.cyan.opacity(0.35)), lineWidth: 4)
            ctx.stroke(main, with: .color(Theme.cyan), lineWidth: 1.5)
        }
        .frame(height: height)
        .background(VizBackground())
    }
}

// MARK: - Filter frequency-response curve

struct FilterCurveView: View {
    let patch: SynthPatch
    var height: CGFloat = 64

    var body: some View {
        Canvas { ctx, size in
            let fMin = log(20.0), fMax = log(18000.0)
            let q = 0.55 + Double(min(max(patch.resonance, 0), 1)) * 7.5

            // 2nd-order magnitude response at normalized frequency x = f/fc.
            func mag(_ f: Double) -> Double {
                let x = f / Double(max(patch.cutoff, 20))
                let x2 = x * x
                let denom = sqrt((1 - x2) * (1 - x2) + x2 / (q * q))
                switch patch.filterType {
                case 1: return (x / q) / max(denom, 1e-9)          // BP
                case 2: return x2 / max(denom, 1e-9)               // HP
                default: return 1 / max(denom, 1e-9)               // LP
                }
            }

            var path = Path()
            let steps = Int(size.width)
            for i in 0...steps {
                let fx = CGFloat(i) / CGFloat(steps)
                let f = exp(fMin + Double(fx) * (fMax - fMin))
                // Map magnitude (dB, -24..+18) to y.
                let db = 20 * log10(max(mag(f), 1e-6))
                let n = (db + 24) / 42
                let y = size.height * (1 - CGFloat(min(max(n, 0), 1)) * 0.92) - 2
                if i == 0 { path.move(to: CGPoint(x: fx * size.width, y: y)) }
                else { path.addLine(to: CGPoint(x: fx * size.width, y: y)) }
            }

            // Fill under the curve.
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [Theme.teal.opacity(0.35), Theme.teal.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(path, with: .color(Theme.teal), lineWidth: 1.5)

            // Cutoff marker.
            let cx = CGFloat((log(Double(max(patch.cutoff, 20))) - fMin) / (fMax - fMin)) * size.width
            ctx.stroke(Path { p in p.move(to: CGPoint(x: cx, y: 0)); p.addLine(to: CGPoint(x: cx, y: size.height)) },
                       with: .color(Theme.frost.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: height)
        .background(VizBackground())
    }
}

// MARK: - ADSR envelope shape

struct ADSRShapeView: View {
    let a: Float, d: Float, s: Float, r: Float
    var color: Color = Theme.cyan
    var height: CGFloat = 44

    var body: some View {
        Canvas { ctx, size in
            // Time-proportional segments with a fixed sustain plateau.
            let ta = Double(max(a, 0.001)), td = Double(max(d, 0.01)), tr = Double(max(r, 0.01))
            let total = ta + td + tr
            let plateau = 0.22 * Double(size.width)
            let scale = (Double(size.width) - plateau) / total
            let xA = ta * scale
            let xD = xA + td * scale
            let xS = xD + plateau
            let yS = Double(size.height) * (1 - Double(min(max(s, 0), 1)) * 0.9) - 2
            let y0 = Double(size.height) - 2, y1 = Double(size.height) * 0.08

            var p = Path()
            p.move(to: CGPoint(x: 0, y: y0))
            p.addLine(to: CGPoint(x: xA, y: y1))
            p.addQuadCurve(to: CGPoint(x: xD, y: yS),
                           control: CGPoint(x: xA + (xD - xA) * 0.3, y: yS + (y1 - yS) * 0.2))
            p.addLine(to: CGPoint(x: xS, y: yS))
            p.addQuadCurve(to: CGPoint(x: size.width, y: y0),
                           control: CGPoint(x: xS + (Double(size.width) - xS) * 0.3, y: y0 - (y0 - yS) * 0.8))

            var fill = p
            fill.addLine(to: CGPoint(x: 0, y: y0))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.3), color.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(p, with: .color(color), lineWidth: 1.5)
        }
        .frame(height: height)
        .background(VizBackground())
    }
}

// MARK: - LFO shape

struct LFOShapeView: View {
    let patch: SynthPatch
    var height: CGFloat = 36

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            let amp = size.height * 0.36 * CGFloat(min(max(patch.lfoDepth, 0), 1)) + 1
            var rng: UInt64 = 0xA11CE
            func rnd() -> Double { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Double(rng >> 40) / Double(1 << 24) * 2 - 1 }

            var p = Path()
            let cycles = 3.0
            let steps = Int(size.width)
            var heldValue = rnd()
            var lastCell = -1
            for i in 0...steps {
                let x = CGFloat(i) / CGFloat(steps)
                let t = Double(x) * cycles
                let v: Double
                switch patch.lfoShape {
                case 1: v = 4 * abs(t - floor(t) - 0.5) - 1                    // tri
                case 2:
                    let cell = Int(t * 4)
                    if cell != lastCell { heldValue = rnd(); lastCell = cell } // S&H
                    v = heldValue
                default: v = sin(t * 2 * .pi)                                  // sine
                }
                let y = midY - CGFloat(v) * amp
                if i == 0 { p.move(to: CGPoint(x: x * size.width, y: y)) }
                else { p.addLine(to: CGPoint(x: x * size.width, y: y)) }
            }
            ctx.stroke(p, with: .color(patch.lfoTarget == 0 ? Color.white.opacity(0.2) : Theme.steel), lineWidth: 1.5)
        }
        .frame(height: height)
        .background(VizBackground())
    }
}

// MARK: - Shared backdrop

struct VizBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black.opacity(0.35))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.frost.opacity(0.08), lineWidth: 1))
    }
}
