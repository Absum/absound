//
//  TransportController.swift
//  Observable bridge between the SwiftUI transport UI and the audio engine.
//  Audio timing is sample-accurate in C++; here we only poll the playhead for
//  the on-screen step indicator.
//

import Combine
import Foundation
import QuartzCore

@MainActor
final class TransportController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var tempo: Double = 112 { didSet { engine.setTempo(tempo) } }
    @Published private(set) var currentStep = -1

    let stepCount = Int(AB_NUM_STEPS)
    let trackLabels = ["Synth", "Kick", "Snare", "Hat"]
    /// Read-only mirror of the seeded pattern for the on-screen grid (M2 makes it editable).
    @Published private(set) var grid: [[Bool]] =
        Array(repeating: Array(repeating: false, count: Int(AB_NUM_STEPS)), count: Int(AB_NUM_TRACKS))

    private let engine = AudioEngine()
    private var displayLink: CADisplayLink?

    init() {
        engine.setTempo(tempo)
        seedDemoPattern()
    }

    func onAppear() { engine.start() }

    func togglePlay() { isPlaying ? stop() : play() }

    func play() {
        engine.start()
        engine.setPlaying(true)
        isPlaying = true
        startPolling()
    }

    func stop() {
        engine.setPlaying(false)
        isPlaying = false
        stopPolling()
        currentStep = -1
    }

    func setTempo(_ bpm: Double) {
        tempo = min(max(bpm, 60), 200)
    }

    // MARK: - Playhead polling (UI only)

    private func startPolling() {
        stopPolling()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 60, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopPolling() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let s = engine.currentStep
        if s != currentStep { currentStep = s }
    }

    // MARK: - Demo content

    /// A simple C-minor groove so Play immediately makes music in M1.
    private func seedDemoPattern() {
        engine.clear()

        func place(_ track: Int, _ step: Int, note: Int, velocity: Int) {
            engine.setStep(track: Int32(track), step: step, note: note, velocity: velocity)
            grid[track][step] = true
        }

        // Drums.
        for s in [0, 4, 8, 11] { place(AB_TRACK_KICK, s, note: 0, velocity: 120) }
        for s in [4, 12] { place(AB_TRACK_SNARE, s, note: 0, velocity: 112) }
        for s in 0..<stepCount {
            place(AB_TRACK_HAT, s, note: 0, velocity: s % 2 == 0 ? 60 : 95)
        }
        // Synth riff — C minor pentatonic (C Eb F G Bb), octave 4/5.
        let riff: [(step: Int, note: Int)] = [
            (0, 60), (3, 63), (6, 67), (8, 70), (10, 67), (13, 63), (14, 65)
        ]
        for n in riff { place(AB_TRACK_SYNTH, n.step, note: n.note, velocity: 105) }
    }
}
