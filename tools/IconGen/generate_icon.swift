// Absound app-icon generator.
//
// Renders a 1024x1024 opaque PNG from the exact Theme palette so the icon stays
// in lock-step with the in-app Arctic design (gradient + teal/cyan aurora glow +
// faint stars + a glowing aurora-waveform ribbon with note dots).
//
// Usage:  swift tools/IconGen/generate_icon.swift <output.png>
// Run from the repo root. macOS only (AppKit).

import AppKit
import Foundation
import ImageIO

// MARK: - Palette (mirrors Absound/Design/Theme.swift)

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255,
            green: CGFloat((h >> 8) & 0xFF) / 255,
            blue: CGFloat(h & 0xFF) / 255,
            alpha: a)
}

let bgTop = hex(0x081519), bgUp = hex(0x0C2630), bgMid = hex(0x103441), bgLow = hex(0x0A1F27)
let teal = hex(0x2EC4B6), cyan = hex(0x64DCFF), steel = hex(0x419EC7), frost = hex(0xC8E6EE)

// Linear sRGB mix — avoids NSColor.blended(...) which can return nil across spaces.
func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let a2 = a.usingColorSpace(.sRGB)!, b2 = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: a2.redComponent * (1 - t) + b2.redComponent * t,
                   green: a2.greenComponent * (1 - t) + b2.greenComponent * t,
                   blue: a2.blueComponent * (1 - t) + b2.blueComponent * t,
                   alpha: a2.alphaComponent * (1 - t) + b2.alphaComponent * t)
}

let S: CGFloat = 1024

// Top-left fractional coordinates -> AppKit points (origin bottom-left).
func pt(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint { NSPoint(x: fx * S, y: (1 - fy) * S) }

// MARK: - Opaque CoreGraphics context (no alpha channel — Apple icons must be opaque)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let cg = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                         bytesPerRow: 0, space: colorSpace,
                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not create CG context")
}
let ctx = NSGraphicsContext(cgContext: cg, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

let full = NSRect(x: 0, y: 0, width: S, height: S)

// 1) Deep Arctic vertical gradient (opaque base).
let bg = NSGradient(colorsAndLocations: (bgTop, 0.0), (bgUp, 0.34), (bgMid, 0.66), (bgLow, 1.0))!
bg.draw(in: full, angle: -90) // -90 => top color at top

// Helper: radial glow bloom from a tinted center fading to clear.
func glow(center: NSPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    let g = NSGradient(colors: [color.withAlphaComponent(alpha), color.withAlphaComponent(0)])!
    g.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

// 2) Aurora glow blooms (echo ArcticBackground's radial gradients).
glow(center: pt(0.30, 0.28), radius: 560, color: teal, alpha: 0.38)
glow(center: pt(0.80, 0.20), radius: 480, color: cyan, alpha: 0.22)
glow(center: pt(0.55, 0.86), radius: 520, color: steel, alpha: 0.16)

// 3) Faint deterministic stars in the upper field.
var seed: UInt64 = 0xAB50_4D17
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 40) / CGFloat(1 << 24) }
for _ in 0..<44 {
    let x = rnd(), y = rnd() * 0.5, r = rnd() * 3.0 + 1.0, op = rnd() * 0.5 + 0.12
    NSColor.white.withAlphaComponent(op).setFill()
    NSBezierPath(ovalIn: NSRect(x: x * S, y: (1 - y) * S, width: r, height: r)).fill()
}

// MARK: - Aurora-waveform ribbon

let x0: CGFloat = 0.12 * S, x1: CGFloat = 0.88 * S
let midY: CGFloat = (1 - 0.52) * S
let steps = 200

// centerline y at parametric u in 0...1
func centerY(_ u: CGFloat) -> CGFloat {
    let env = sin(.pi * u)                    // tapers to 0 at both ends
    let wave = sin(u * .pi * 2 * 1.5 - .pi / 5)
    return midY + wave * 168 * (0.45 + 0.55 * env)
}
// half-thickness at u (thin at ends, fat in the middle)
func halfT(_ u: CGFloat) -> CGFloat { 16 + 70 * sin(.pi * u) }

func centerPath(width: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.lineWidth = width
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    for i in 0...steps {
        let u = CGFloat(i) / CGFloat(steps)
        let x = x0 + (x1 - x0) * u
        let pNT = NSPoint(x: x, y: centerY(u))
        if i == 0 { p.move(to: pNT) } else { p.line(to: pNT) }
    }
    return p
}

// 4) Glow bloom behind the ribbon: wide, low-alpha strokes.
cg.saveGState()
for (w, a) in [(150.0, 0.06), (104.0, 0.10), (66.0, 0.18)] as [(CGFloat, CGFloat)] {
    mix(teal, cyan, 0.3).withAlphaComponent(a).setStroke()
    centerPath(width: w).stroke()
}
cg.restoreGState()

// 5) Filled ribbon body with a teal->cyan horizontal gradient.
let ribbon = NSBezierPath()
for i in 0...steps {                                  // top edge forward
    let u = CGFloat(i) / CGFloat(steps)
    let x = x0 + (x1 - x0) * u
    let p2 = NSPoint(x: x, y: centerY(u) + halfT(u))
    if i == 0 { ribbon.move(to: p2) } else { ribbon.line(to: p2) }
}
for i in stride(from: steps, through: 0, by: -1) {    // bottom edge back
    let u = CGFloat(i) / CGFloat(steps)
    let x = x0 + (x1 - x0) * u
    ribbon.line(to: NSPoint(x: x, y: centerY(u) - halfT(u)))
}
ribbon.close()

cg.saveGState()
ribbon.addClip()
let ribbonGrad = NSGradient(colors: [mix(steel, teal, 0.25), teal, cyan],
                            atLocations: [0.0, 0.5, 1.0], colorSpace: .sRGB)!
ribbonGrad.draw(in: ribbon.bounds, angle: 0)
cg.restoreGState()

// 6) Bright frost highlight skimming the top edge of the ribbon.
let hi = NSBezierPath()
hi.lineWidth = 7
hi.lineCapStyle = .round
for i in 0...steps {
    let u = CGFloat(i) / CGFloat(steps)
    let x = x0 + (x1 - x0) * u
    let p3 = NSPoint(x: x, y: centerY(u) + halfT(u) - 5)
    if i == 0 { hi.move(to: p3) } else { hi.line(to: p3) }
}
frost.withAlphaComponent(0.55).setStroke()
hi.stroke()

// 7) Glowing "note" dots riding the wave.
func noteDot(u: CGFloat, r: CGFloat, color: NSColor) {
    let x = x0 + (x1 - x0) * u
    let c = NSPoint(x: x, y: centerY(u))
    glow(center: c, radius: r * 4.5, color: color, alpha: 0.5)
    color.withAlphaComponent(0.95).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
    NSColor.white.withAlphaComponent(0.9).setFill()
    let ir = r * 0.42
    NSBezierPath(ovalIn: NSRect(x: c.x - ir, y: c.y - ir, width: ir * 2, height: ir * 2)).fill()
}
noteDot(u: 0.18, r: 17, color: cyan)
noteDot(u: 0.52, r: 22, color: frost)
noteDot(u: 0.84, r: 17, color: teal)

// MARK: - Write PNG

NSGraphicsContext.restoreGraphicsState()
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
guard let image = cg.makeImage() else { fatalError("makeImage failed") }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("PNG destination failed")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("PNG write failed") }
print("Wrote \(outPath) (\(Int(S))x\(Int(S)), opaque)")
