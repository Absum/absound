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
    @StateObject private var toast = ToastCenter()
    @State private var showOnboarding = false
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
            MixView(transport: transport)
                .tag(3)
                .tabItem { Label("Mix", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.teal)
        .preferredColorScheme(.dark)
        .environmentObject(patchLibrary)
        .environmentObject(songLibrary)
        .environmentObject(toast)
        .overlay { ToastOverlay().environmentObject(toast) }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                selection = 0
                transport.sparkIdea()
                if !transport.isPlaying { transport.playPattern() }
                toast.show("New idea sparked — tap ✨ to reroll", icon: "sparkles")
            }
            .environmentObject(toast)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive { transport.saveNow() }
        }
        .onAppear {
            #if DEBUG
            transport.notify = { [weak toast] msg, icon in toast?.show(msg, icon: icon) }
            if !UserDefaults.standard.bool(forKey: "didOnboarding") { showOnboarding = true }
            let env = ProcessInfo.processInfo.environment
            switch env["ABSOUND_START_TAB"] {
            case "sounds": selection = 1
            case "song": selection = 2
            case "mix": selection = 3
            default: break
            }
            if env["ABSOUND_AUTOPLAY"] != nil { transport.playPattern() }
            if env["ABSOUND_ONBOARD"] != nil { showOnboarding = true }
            #endif
        }
    }
}

#Preview {
    ContentView()
}
