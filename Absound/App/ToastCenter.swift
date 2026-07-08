//
//  ToastCenter.swift
//  Transient action feedback: "Sound saved", "Song deleted", etc. Success and
//  info use toasts (non-blocking, auto-dismissing); confirmations stay dialogs.
//

import SwiftUI

@MainActor
final class ToastCenter: ObservableObject {
    struct Toast: Equatable {
        let message: String
        let icon: String
    }

    @Published private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, icon: String = "checkmark.circle.fill") {
        current = Toast(message: message, icon: icon)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled { current = nil }
        }
    }
}

struct ToastOverlay: View {
    @EnvironmentObject var toast: ToastCenter

    var body: some View {
        VStack {
            if let t = toast.current {
                HStack(spacing: 8) {
                    Image(systemName: t.icon).font(.system(size: 14)).foregroundStyle(Theme.teal)
                    Text(t.message).font(Theme.body(14)).foregroundStyle(Theme.frost)
                }
                .padding(.vertical, 10).padding(.horizontal, 18)
                .background(Capsule().fill(Theme.bgUp.opacity(0.96)))
                .overlay(Capsule().stroke(Theme.teal.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(duration: 0.35), value: toast.current)
        .allowsHitTesting(false)
    }
}
