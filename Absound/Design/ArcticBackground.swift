//
//  ArcticBackground.swift
//  Dark glacial night — now alive: the aurora drifts and breathes, the glow
//  blooms wander, the stars twinkle. Rendered as a single Canvas driven by
//  TimelineView at a capped ~20 fps, so redraws stay on this layer only (no
//  view-tree invalidation) and the GPU/battery cost stays negligible.
//  Honors Reduce Motion with the original static composition.
//

import SwiftUI

struct ArcticBackground: View {
    /// Brightens the aurora while the transport is playing.
    var glow: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Canvas { ctx, size in Self.draw(ctx, size: size, t: 0, glow: glow, animated: false) }
                .ignoresSafeArea()
                .background(Theme.bgGradient.ignoresSafeArea())
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in Self.draw(ctx, size: size, t: t, glow: glow, animated: true) }
            }
            .ignoresSafeArea()
            .background(Theme.bgGradient.ignoresSafeArea())
        }
    }

    // MARK: - Drawing

    private static func draw(_ ctx: GraphicsContext, size: CGSize, t: TimeInterval, glow: Bool, animated: Bool) {
        // Slow master clocks. Everything drifts and breathes off these.
        let drift = animated ? t * 0.06 : 0.0
        let breathe = animated ? 0.5 + 0.5 * sin(t * 0.23) : 0.5

        // --- Aurora glow blooms, wandering slowly across the sky ---
        func bloom(_ cx: Double, _ cy: Double, _ radius: Double, _ color: Color, _ alpha: Double) {
            let center = CGPoint(x: cx * size.width, y: cy * size.height)
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .radialGradient(Gradient(colors: [color.opacity(alpha), .clear]),
                                      center: center, startRadius: 0, endRadius: radius))
        }
        let baseA = glow ? 0.42 : 0.26
        bloom(0.32 + 0.06 * sin(drift), 0.30 + 0.04 * cos(drift * 1.3), 320,
              Theme.teal, baseA * (0.8 + 0.4 * breathe))
        bloom(0.78 + 0.05 * cos(drift * 0.8), 0.22 + 0.05 * sin(drift * 1.1), 280,
              Theme.cyan, 0.18 * (0.7 + 0.6 * (1 - breathe)))
        bloom(0.55 + 0.08 * sin(drift * 0.6 + 2.0), 0.55, 360,
              Theme.steel, 0.08 * (0.6 + 0.8 * breathe))

        // --- Stars with per-star twinkle ---
        var rng = SeededRNG(seed: 0xA11CE)
        for i in 0..<46 {
            let x = rng.unit(), y = rng.unit() * 0.55
            let r = rng.unit() * 1.5 + 0.4
            let baseOp = rng.unit() * 0.6 + 0.15
            let twinkle = animated ? 0.65 + 0.35 * sin(t * (0.4 + rng.unit() * 1.2) + Double(i) * 1.7) : 1.0
            ctx.fill(Path(ellipseIn: CGRect(x: x * size.width, y: y * size.height, width: r, height: r)),
                     with: .color(.white.opacity(baseOp * twinkle * 0.7)))
        }

        // --- Two counter-drifting aurora ridges near the lower third ---
        func ridge(baseline: Double, amplitude: Double, phase: Double, alpha: Double, blurTint: Color) {
            var path = Path()
            let midY = size.height * baseline
            path.move(to: CGPoint(x: 0, y: midY))
            let steps = 64
            for i in 0...steps {
                let f = Double(i) / Double(steps)
                let y = midY
                    + sin(f * .pi * 2 + phase) * amplitude
                    + sin(f * .pi * 4.7 + phase * 1.7) * amplitude * 0.35   // second harmonic shimmer
                path.addLine(to: CGPoint(x: size.width * f, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()

            var layer = ctx
            layer.addFilter(.blur(radius: 18))
            layer.fill(path, with: .linearGradient(
                Gradient(colors: [blurTint.opacity(alpha), Theme.cyan.opacity(alpha * 0.35), .clear]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
        }
        let ridgeA = (glow ? 0.5 : 0.32) * (0.75 + 0.5 * breathe)
        ridge(baseline: 0.70, amplitude: 22 + 6 * breathe, phase: .pi / 3 + drift * 2.2,
              alpha: ridgeA, blurTint: Theme.teal)
        ridge(baseline: 0.76, amplitude: 14 + 5 * (1 - breathe), phase: 1.1 - drift * 1.6,
              alpha: ridgeA * 0.45, blurTint: Theme.cyan)
    }
}

private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    /// Uniform value in [0, 1).
    mutating func unit() -> Double { Double(next() >> 40) / Double(1 << 24) }
}
