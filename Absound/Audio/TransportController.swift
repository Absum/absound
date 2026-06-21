//
//  TransportController.swift
//  Observable bridge between the SwiftUI Studio and the audio engine. Owns the
//  editable Pattern; every edit updates the model and pushes to the C++ core so
//  changes audition live. Audio timing stays sample-accurate in C++; here we only
//  poll the playhead for the on-screen step indicator.
//

import Combine
import Foundation
import QuartzCore

@MainActor
final class TransportController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var tempo: Double = 112 { didSet { engine.setTempo(tempo) } }
    @Published private(set) var currentStep = -1
    @Published private(set) var pattern: Pattern

    private let engine = AudioEngine()
    private var displayLink: CADisplayLink?

    let stepCount = Pattern.stepCount

    var context: MusicalContext { pattern.context }
    var preset: SynthPreset { SynthPreset(rawValue: pattern.presetRaw) ?? .pluck }
    /// Editor rows span two octaves of the current scale, plus the top root.
    var melodyRowCount: Int { pattern.context.scale.degreeCount * 2 + 1 }

    init() {
        pattern = .demo()
        engine.setTempo(tempo)
        pushAll()
    }

    func onAppear() { engine.start() }

    // MARK: - Transport

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

    func setTempo(_ bpm: Double) { tempo = min(max(bpm, 60), 200) }

    // MARK: - Editing (model + live engine)

    func toggleDrum(_ lane: DrumLane, step: Int) {
        let on = !pattern.drums[lane.rawValue][step]
        pattern.drums[lane.rawValue][step] = on
        engine.setStep(track: lane.engineTrack, step: step, note: 0, velocity: on ? lane.velocity : 0)
        if on { engine.start(); engine.noteOn(track: lane.engineTrack, note: 0, velocity: Float(lane.velocity) / 127) }
    }

    func toggleMelody(row: Int, step: Int) {
        if pattern.melody[step] == row {
            pattern.melody[step] = nil
            engine.setStep(track: Int32(AB_TRACK_SYNTH), step: step, note: 0, velocity: 0)
        } else {
            pattern.melody[step] = row
            let midi = pattern.context.midiNote(forRow: row)
            engine.setStep(track: Int32(AB_TRACK_SYNTH), step: step, note: midi, velocity: pattern.melodyVelocity)
            engine.start(); engine.noteOn(track: Int32(AB_TRACK_SYNTH), note: midi, velocity: 0.9)
        }
    }

    func setRoot(_ root: Int) {
        pattern.contextRoot = ((root % 12) + 12) % 12
        repushMelody()
    }

    func setScale(_ scale: Scale) {
        pattern.scaleRaw = scale.rawValue
        // Keep melody rows within the new scale's visible range.
        let maxRow = scale.degreeCount * 2
        for i in pattern.melody.indices {
            if let row = pattern.melody[i], row > maxRow { pattern.melody[i] = maxRow }
        }
        repushMelody()
    }

    func setPreset(_ preset: SynthPreset) {
        pattern.presetRaw = preset.rawValue
        engine.setSynthPreset(preset.rawValue)
    }

    func clear() {
        for lane in DrumLane.allCases { pattern.drums[lane.rawValue] = Array(repeating: false, count: stepCount) }
        pattern.melody = Array(repeating: nil, count: stepCount)
        engine.clear()
    }

    // MARK: - Engine sync

    private func pushAll() {
        engine.clear()
        for lane in DrumLane.allCases {
            for s in 0..<stepCount where pattern.drums[lane.rawValue][s] {
                engine.setStep(track: lane.engineTrack, step: s, note: 0, velocity: lane.velocity)
            }
        }
        repushMelody()
        engine.setSynthPreset(pattern.presetRaw)
    }

    private func repushMelody() {
        let ctx = pattern.context
        for s in 0..<stepCount {
            if let row = pattern.melody[s] {
                engine.setStep(track: Int32(AB_TRACK_SYNTH), step: s, note: ctx.midiNote(forRow: row), velocity: pattern.melodyVelocity)
            } else {
                engine.setStep(track: Int32(AB_TRACK_SYNTH), step: s, note: 0, velocity: 0)
            }
        }
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
}
