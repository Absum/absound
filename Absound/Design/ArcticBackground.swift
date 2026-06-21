//
//  ArcticBackground.swift
//  Dark glacial night: deep gradient, teal/cyan aurora glow, faint stars,
//  and a luminous aurora ridge across the lower third.
//

import SwiftUI

struct ArcticBackground: View {
    /// Drives a gentle brightening of the aurora when the note is in tune.
    var glow: Bool = false

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()

            // Soft aurora glow blooms (echo of absum.net's radial gradients).
            RadialGradient(colors: [Theme.teal.opacity(glow ? 0.42 : 0.26), .clear],
                           center: .init(x: 0.32, y: 0.30), startRadius: 0, endRadius: 320)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.cyan.opacity(0.18), .clear],
                           center: .init(x: 0.78, y: 0.22), startRadius: 0, endRadius: 280)
                .ignoresSafeArea()

            Stars().ignoresSafeArea().opacity(0.7)

            // Aurora ridge near the lower third.
            AuroraRidge(baseline: 0.70, amplitude: 22)
                .fill(LinearGradient(
                    colors: [Theme.teal.opacity(glow ? 0.5 : 0.32),
                             Theme.cyan.opacity(0.12), .clear],
                    startPoint: .leading, endPoint: .trailing))
                .blur(radius: 18)
                .ignoresSafeArea()
        }
    }
}

/// A smooth filled wave used for the aurora ridge.
private struct AuroraRidge: Shape {
    var baseline: CGFloat   // fraction of height where the crest sits
    var amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.height * baseline
        path.move(to: CGPoint(x: 0, y: midY))
        let steps = 64
        for i in 0...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let x = rect.width * f
            let y = midY + sin(f * .pi * 2 + .pi / 3) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// Deterministic scattered stars in the upper region.
private struct Stars: View {
    private let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, op: Double)] = {
        var rng = SeededRNG(seed: 0xA11CE)
        return (0..<46).map { _ in
            (CGFloat(rng.unit()),
             CGFloat(rng.unit() * 0.55),
             CGFloat(rng.unit() * 1.5 + 0.4),
             rng.unit() * 0.6 + 0.15)
        }
    }()

    var body: some View {
        Canvas { ctx, size in
            for s in stars {
                let rect = CGRect(x: s.x * size.width, y: s.y * size.height,
                                  width: s.r, height: s.r)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(s.op)))
            }
        }
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
