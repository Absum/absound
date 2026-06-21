//
//  TransportController.swift
//  Bridge between the SwiftUI Studio and the audio engine. Owns the editable
//  multi-track Pattern, manages the engine's track pool, and pushes every edit so
//  changes audition live. Audio timing stays sample-accurate in C++; here we only
//  poll the playhead for the on-screen step indicator / Highway scroll.
//

import Combine
import Foundation
import QuartzCore

@MainActor
final class TransportController: ObservableObject {

    enum Selection: Equatable { case track(UUID); case drums }

    @Published private(set) var isPlaying = false
    @Published var tempo: Double = 112 { didSet { engine.setTempo(tempo) } }
    @Published private(set) var currentStep = -1
    @Published private(set) var playPosition: Double = -1
    @Published var isRecording = false
    @Published var showShadow = true   // ghost-notes of other layers in the melody editor
    @Published private(set) var pattern: Pattern
    @Published var selection: Selection

    private let engine = AudioEngine()
    private var displayLink: CADisplayLink?

    let stepCount = Pattern.stepCount

    init() {
        var p = Pattern.demo()
        // Register every layer with the engine and capture its handle.
        for i in p.tracks.indices {
            let t = p.tracks[i]
            p.tracks[i].engineId = engine.addTrack(kind: t.kind.rawValue, sound: t.sound)
        }
        pattern = p
        // Select the last melodic layer (the lead) by default.
        selection = p.tracks.last(where: { $0.kind == .synth }).map { .track($0.id) } ?? .drums
        engine.setTempo(tempo)
        pushAllSteps()
    }

    func onAppear() { engine.start() }

    // MARK: - Derived

    var context: MusicalContext { pattern.context }
    var melodyRowCount: Int { pattern.context.scale.degreeCount * 2 + 1 }
    var melodicTracks: [LayerTrack] { pattern.tracks.filter { $0.kind == .synth } }
    var drumTracks: [LayerTrack] { pattern.tracks.filter { $0.kind == .drum } }

    var selectedTrackId: UUID? { if case .track(let id) = selection { return id }; return nil }
    var selectedTrack: LayerTrack? { selectedTrackId.flatMap { id in pattern.tracks.first { $0.id == id } } }
    var selectedMelody: [Int?] { selectedTrack?.melody ?? Array(repeating: nil, count: stepCount) }
    /// Melodies of the other synth layers (for shadow/ghost rendering).
    var otherMelodies: [[Int?]] {
        guard let sel = selectedTrackId else { return [] }
        return pattern.tracks.filter { $0.kind == .synth && $0.id != sel }.map { $0.melody }
    }
    var selectedPreset: SynthPreset { SynthPreset(rawValue: selectedTrack?.sound ?? 0) ?? .pluck }

    private func index(_ id: UUID) -> Int? { pattern.tracks.firstIndex { $0.id == id } }

    // MARK: - Transport

    func togglePlay() { isPlaying ? stop() : play() }
    func play() { engine.start(); engine.setPlaying(true); isPlaying = true; startPolling() }
    func stop() { engine.setPlaying(false); isPlaying = false; stopPolling(); currentStep = -1; playPosition = -1 }
    func setTempo(_ bpm: Double) { tempo = min(max(bpm, 60), 200) }

    // MARK: - Layer management

    func addSynthLayer(_ preset: SynthPreset) {
        var t = LayerTrack.synth(preset)
        t.engineId = engine.addTrack(kind: TrackKind.synth.rawValue, sound: preset.rawValue)
        guard t.engineId >= 0 else { return }
        pattern.tracks.append(t)
        selection = .track(t.id)
    }

    func addDrumLayer(_ sound: DrumSound) {
        var t = LayerTrack.drum(sound)
        t.engineId = engine.addTrack(kind: TrackKind.drum.rawValue, sound: sound.rawValue)
        guard t.engineId >= 0 else { return }
        pattern.tracks.append(t)
    }

    func removeTrack(_ id: UUID) {
        guard let i = index(id) else { return }
        engine.removeTrack(pattern.tracks[i].engineId)
        let wasSelected = selectedTrackId == id
        pattern.tracks.remove(at: i)
        if wasSelected { selection = melodicTracks.last.map { .track($0.id) } ?? .drums }
    }

    func toggleMute(_ id: UUID) {
        guard let i = index(id) else { return }
        pattern.tracks[i].muted.toggle()
        engine.setTrackMute(pattern.tracks[i].engineId, muted: pattern.tracks[i].muted)
    }

    func setTrackSound(_ id: UUID, sound: Int) {
        guard let i = index(id) else { return }
        pattern.tracks[i].sound = sound
        engine.setTrackSound(pattern.tracks[i].engineId, sound: sound)
    }

    func select(_ id: UUID) { selection = .track(id) }
    func selectDrums() { selection = .drums }

    // MARK: - Editing: melody (operates on the selected synth track)

    func toggleMelody(row: Int, step: Int) {
        guard let i = selectedTrackId.flatMap(index) else { return }
        if pattern.tracks[i].melody[step] == row {
            pattern.tracks[i].melody[step] = nil
            engine.setStep(track: pattern.tracks[i].engineId, step: step, note: 0, velocity: 0)
        } else {
            pattern.tracks[i].melody[step] = row
            let midi = pattern.context.midiNote(forRow: row)
            engine.setStep(track: pattern.tracks[i].engineId, step: step, note: midi, velocity: pattern.tracks[i].melodyVelocity)
            engine.start(); engine.noteOn(track: pattern.tracks[i].engineId, note: midi, velocity: 0.9)
        }
    }

    func placeMelody(row: Int, step: Int) {
        guard let i = selectedTrackId.flatMap(index) else { return }
        pattern.tracks[i].melody[step] = row
        engine.setStep(track: pattern.tracks[i].engineId, step: step,
                       note: pattern.context.midiNote(forRow: row), velocity: pattern.tracks[i].melodyVelocity)
    }

    func audition(row: Int) {
        guard let t = selectedTrack else { return }
        engine.start()
        engine.noteOn(track: t.engineId, note: pattern.context.midiNote(forRow: row), velocity: 0.9)
    }

    func toggleRecord() { isRecording.toggle() }

    func highwayTap(row: Int) {
        audition(row: row)
        guard isRecording, isPlaying, playPosition >= 0 else { return }
        placeMelody(row: row, step: Int(playPosition.rounded()) % stepCount)
    }

    // MARK: - Editing: drums

    func toggleDrum(_ id: UUID, step: Int) {
        guard let i = index(id) else { return }
        let on = !pattern.tracks[i].drumSteps[step]
        pattern.tracks[i].drumSteps[step] = on
        let t = pattern.tracks[i]
        engine.setStep(track: t.engineId, step: step, note: 0, velocity: on ? t.drumVelocity : 0)
        if on { engine.start(); engine.noteOn(track: t.engineId, note: 0, velocity: Float(t.drumVelocity) / 127) }
    }

    // MARK: - Context + clear

    func setRoot(_ root: Int) { pattern.contextRoot = ((root % 12) + 12) % 12; repushAllMelodies() }

    func setScale(_ scale: Scale) {
        pattern.scaleRaw = scale.rawValue
        let maxRow = scale.degreeCount * 2
        for i in pattern.tracks.indices where pattern.tracks[i].kind == .synth {
            for s in pattern.tracks[i].melody.indices {
                if let row = pattern.tracks[i].melody[s], row > maxRow { pattern.tracks[i].melody[s] = maxRow }
            }
        }
        repushAllMelodies()
    }

    func clearCurrent() {
        switch selection {
        case .drums:
            for i in pattern.tracks.indices where pattern.tracks[i].kind == .drum {
                pattern.tracks[i].drumSteps = Array(repeating: false, count: stepCount)
                engine.clearTrack(pattern.tracks[i].engineId)
            }
        case .track(let id):
            guard let i = index(id) else { return }
            pattern.tracks[i].melody = Array(repeating: nil, count: stepCount)
            engine.clearTrack(pattern.tracks[i].engineId)
        }
    }

    // MARK: - Engine sync

    private func pushAllSteps() {
        engine.clearAll()
        for t in pattern.tracks {
            if t.kind == .drum {
                for s in 0..<stepCount where t.drumSteps[s] {
                    engine.setStep(track: t.engineId, step: s, note: 0, velocity: t.drumVelocity)
                }
            } else {
                pushMelody(t)
            }
        }
    }

    private func pushMelody(_ t: LayerTrack) {
        let ctx = pattern.context
        for s in 0..<stepCount {
            if let row = t.melody[s] {
                engine.setStep(track: t.engineId, step: s, note: ctx.midiNote(forRow: row), velocity: t.melodyVelocity)
            } else {
                engine.setStep(track: t.engineId, step: s, note: 0, velocity: 0)
            }
        }
    }

    private func repushAllMelodies() {
        for t in pattern.tracks where t.kind == .synth { pushMelody(t) }
    }

    // MARK: - Playhead polling

    private func startPolling() {
        stopPolling()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    private func stopPolling() { displayLink?.invalidate(); displayLink = nil }

    @objc private func tick() {
        let s = engine.currentStep
        if s != currentStep { currentStep = s }
        playPosition = engine.playPosition
    }
}
