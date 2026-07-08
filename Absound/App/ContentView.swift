//
//  ContentView.swift
//  App shell. M0: a themed empty studio over the inherited Arctic backdrop,
//  with placeholder tabs the later milestones fill in.
//

import SwiftUI

struct ContentView: View {
    @State private var selection = 0
    @StateObject private var transport = TransportController()

    var body: some View {
        TabView(selection: $selection) {
            PatternStudioView(transport: transport)
                .tag(0)
                .tabItem { Label("Studio", systemImage: "square.grid.3x3.fill") }
            SongArrangerView(transport: transport)
                .tag(1)
                .tabItem { Label("Song", systemImage: "rectangle.stack.fill") }
            ComingSoon(title: "Settings")
                .tag(2)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.teal)
        .preferredColorScheme(.dark)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["ABSOUND_START_TAB"] == "song" { selection = 1 }
            #endif
        }
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
