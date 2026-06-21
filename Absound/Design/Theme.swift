//
//  Theme.swift
//  Arctic palette + Rajdhani type, taken from absum.net — the DARK variation:
//  a deep glacial petrol-navy night lit by teal/cyan aurora glow.
//

import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    // Deep background stops (top → bottom).
    static let bgTop  = Color(hex: 0x081519)
    static let bgUp   = Color(hex: 0x0C2630)
    static let bgMid  = Color(hex: 0x103441)
    static let bgLow  = Color(hex: 0x0A1F27)

    // Accents.
    static let teal  = Color(hex: 0x2EC4B6)   // signature accent / in-tune
    static let cyan  = Color(hex: 0x64DCFF)
    static let steel = Color(hex: 0x419EC7)
    static let frost = Color(hex: 0xC8E6EE)   // near-white cool text/icons

    static let bgGradient = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: bgTop, location: 0.00),
            .init(color: bgUp, location: 0.34),
            .init(color: bgMid, location: 0.66),
            .init(color: bgLow, location: 1.00),
        ]),
        startPoint: .top, endPoint: .bottom)

    // Rajdhani weights (bundled).
    static func display(_ size: CGFloat) -> Font { .custom("Rajdhani-SemiBold", size: size) }
    static func title(_ size: CGFloat) -> Font { .custom("Rajdhani-Medium", size: size) }
    static func body(_ size: CGFloat) -> Font { .custom("Rajdhani-Regular", size: size) }
    static func light(_ size: CGFloat) -> Font { .custom("Rajdhani-Light", size: size) }
}
