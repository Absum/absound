//
//  AbsoundApp.swift
//  Absound — compose electronic music, learn theory as you go.
//

import SwiftUI
import UIKit

@main
struct AbsoundApp: App {
    init() {
        configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// One source of truth for the tab bar: the system translucent blur with the
    /// Arctic accent tints, matched for standard + scroll-edge so every tab agrees.
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let normal = UIColor(Theme.frost.opacity(0.55))
        let selected = UIColor(Theme.teal)
        appearance.stackedLayoutAppearance.normal.iconColor = normal
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normal]
        appearance.stackedLayoutAppearance.selected.iconColor = selected
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selected]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
