//
//  ContentView.swift
//  App shell. M0: a themed empty studio over the inherited Arctic backdrop,
//  with placeholder tabs the later milestones fill in.
//

import SwiftUI

struct ContentView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            StudioPlaceholder()
                .tag(0)
                .tabItem { Label("Studio", systemImage: "square.grid.3x3.fill") }
            ComingSoon(title: "Song")
                .tag(1)
                .tabItem { Label("Song", systemImage: "rectangle.stack.fill") }
            ComingSoon(title: "Settings")
                .tag(2)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.teal)
        .preferredColorScheme(.dark)
    }
}

/// Landing surface for the Pattern Studio (the app's spine). M0 placeholder.
private struct StudioPlaceholder: View {
    var body: some View {
        ZStack {
            ArcticBackground()
            VStack(spacing: 12) {
                Text("ABSOUND")
                    .font(Theme.display(48))
                    .foregroundStyle(Theme.frost)
                    .tracking(6)
                Text("compose · learn · export")
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.teal)
                    .tracking(2)
                Text(synthVersion)
                    .font(Theme.light(13))
                    .foregroundStyle(Theme.frost.opacity(0.4))
                    .padding(.top, 24)
            }
        }
    }

    /// Calls into the C++ DSP core — proves the Swift<->C++ bridge links at runtime.
    private var synthVersion: String {
        guard let cString = ab_synth_version() else { return "" }
        return String(cString: cString)
    }
}

private struct ComingSoon: View {
    let title: String
    var body: some View {
        ZStack {
            ArcticBackground()
            Text(title)
                .font(Theme.display(34))
                .foregroundStyle(Theme.frost.opacity(0.7))
        }
    }
}

#Preview {
    ContentView()
}
