//
//  ContentView.swift
//  App shell. M0: a themed empty studio over the inherited Arctic backdrop,
//  with placeholder tabs the later milestones fill in.
//

import SwiftUI

struct ContentView: View {
    @State private var selection = 0
    @StateObject private var transport = TransportController()
    @StateObject private var patchLibrary = PatchLibrary()
    @StateObject private var songLibrary = SongLibrary()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selection) {
            PatternStudioView(transport: transport)
                .tag(0)
                .tabItem { Label("Studio", systemImage: "square.grid.3x3.fill") }
            SoundsTabView(transport: transport)
                .tag(1)
                .tabItem { Label("Sounds", systemImage: "slider.vertical.3") }
            SongArrangerView(transport: transport)
                .tag(2)
                .tabItem { Label("Song", systemImage: "rectangle.stack.fill") }
            ComingSoon(title: "Settings")
                .tag(3)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.teal)
        .preferredColorScheme(.dark)
        .environmentObject(patchLibrary)
        .environmentObject(songLibrary)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive { transport.saveNow() }
        }
        .onAppear {
            #if DEBUG
            switch ProcessInfo.processInfo.environment["ABSOUND_START_TAB"] {
            case "sounds": selection = 1
            case "song": selection = 2
            default: break
            }
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
