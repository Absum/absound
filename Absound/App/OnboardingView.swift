//
//  OnboardingView.swift
//  Three-screen first-run intro: compose (you can't hit a wrong note),
//  design (a real synth underneath), ship (arrange, mix, export). Ends with
//  "Spark your first idea", which generates and plays a full idea immediately.
//

import SwiftUI

struct OnboardingView: View {
    var onSpark: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let text: String
    }
    private let pages = [
        Page(icon: "square.grid.3x3.middle.filled",
             title: "Compose without fear",
             text: "Every row in the grid is locked to your key — you literally can't hit a wrong note. Paint melodies, drum grooves, or tap ✨ Spark and get a full idea instantly."),
        Page(icon: "slider.vertical.3",
             title: "A real synth underneath",
             text: "Every sound is a full synthesizer: oscillators, filters, envelopes, and a chain of 13 studio effects. Tweak a preset in the Sound Lab or design your own from scratch."),
        Page(icon: "square.and.arrow.up",
             title: "Arrange, mix, ship",
             text: "Chain patterns into a song, balance it in the Mix tab with real meters, and export MIDI straight into Logic or any DAW. Your ideas leave the app production-ready."),
    ]

    var body: some View {
        ZStack {
            ArcticBackground()
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(Theme.body(14)).foregroundStyle(Theme.frost.opacity(0.5))
                }
                Spacer()
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                        VStack(spacing: 18) {
                            Image(systemName: p.icon)
                                .font(.system(size: 52, weight: .light))
                                .foregroundStyle(Theme.cyan)
                                .shadow(color: Theme.cyan.opacity(0.6), radius: 14)
                            Text(p.title)
                                .font(Theme.display(26)).foregroundStyle(Theme.frost)
                                .multilineTextAlignment(.center)
                            Text(p.text)
                                .font(Theme.body(15)).foregroundStyle(Theme.frost.opacity(0.75))
                                .multilineTextAlignment(.center).lineSpacing(4)
                                .padding(.horizontal, 12)
                        }
                        .tag(i)
                        .padding(.bottom, 40)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 320)
                Spacer()
                if page == pages.count - 1 {
                    Button {
                        finish()
                        onSpark()
                    } label: {
                        Label("Spark your first idea", systemImage: "sparkles")
                            .font(Theme.title(17)).foregroundStyle(Theme.bgTop)
                            .padding(.vertical, 14).frame(maxWidth: .infinity)
                            .background(Capsule().fill(
                                LinearGradient(colors: [Theme.cyan, Theme.teal],
                                               startPoint: .leading, endPoint: .trailing)))
                            .shadow(color: Theme.cyan.opacity(0.5), radius: 10)
                    }
                } else {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("Next")
                            .font(Theme.title(17)).foregroundStyle(Theme.frost)
                            .padding(.vertical, 14).frame(maxWidth: .infinity)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
            }
            .padding(24)
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "didOnboarding")
        dismiss()
    }
}
