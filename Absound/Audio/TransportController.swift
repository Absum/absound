//
//  TransportController.swift
//  Bridge between the SwiftUI Studio/Song and the audio engine. Owns the Project
//  (global layers + patterns + song), manages the engine track pool, and pushes
//  every edit so changes audition live. Editing targets the current pattern; the
//  Song tab plays the whole arrangement.
//

import Combine
import Foundation
import QuartzCore

@MainActor
final class TransportController: ObservableObject {

    enum Selection: Equatable { case track(UUID); case drums }

    @Published private(set) var isPlaying = false
    @Published private(set) var songPlaying = false
    @Published var tempo: Double = 112 {
        didSet {
            engine.setTempo(tempo)
            if project.tempo != tempo { project.tempo = tempo }   // keep persisted copy in sync
        }
    }
    @Published private(set) var currentStep = -1
    @Published private(set) var playPosition: Double = -1
    @Published private(set) var currentPattern = 0
    @Published private(set) var songPosition = -1
    @Published var isRecording = false
    @Published var showShadow = true
    @Published private(set) var project: Project
    @Published var selection: Selection

    private let engine = AudioEngine()
    private var displayLink: CADisplayLink?
    private let store = ProjectStore()
    private var saveCancellable: AnyCancellable?
    /// Dedicated engine track for the standalone Sound Lab (Sounds tab) — no steps,
    /// only live auditions, so sound design works without touching any layer.
    private(set) var previewEngineId: Int = -1

    let stepCount = Project.stepCount

    init() {
        var p = store.load() ?? Project.demo()
        // Re-register every layer with the engine: persisted engineIds are stale handles.
        for i in p.layers.indices {
            let l = p.layers[i]
            p.layers[i].engineId = engine.addTrack(kind: l.kind.rawValue, sound: l.sound)
            if let patch = l.patch { engine.setPatch(p.layers[i].engineId, patch.toAB()) }
        }
        project = p
        selection = p.layers.last(where: { $0.kind == .synth }).map { .track($0.id) } ?? .drums
        tempo = p.tempo
        engine.setTempo(p.tempo)
        engine.setSongMode(false)
        engine.setPattern(p.currentPatternIndex)
        engine.setSong(p.song)
        pushEverything()

        previewEngineId = engine.addTrack(kind: TrackKind.synth.rawValue, sound: 0)

        // Autosave: any project mutation persists after a short quiet period.
        saveCancellable = $project
            .dropFirst()
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [store] in store.save($0) }
    }

    /// Immediate save (called when the app backgrounds).
    func saveNow() { store.save(project) }

    // MARK: - Standalone sound design (Sounds tab)

    func applyPreviewPatch(_ patch: SynthPatch) {
        guard previewEngineId >= 0 else { return }
        engine.setPatch(previewEngineId, patch.toAB())
    }
    func auditionPreview(row: Int) {
        guard previewEngineId >= 0 else { return }
        engine.start()
        engine.noteOn(track: previewEngineId, note: context.midiNote(forRow: row), velocity: 0.9)
    }

    func onAppear() { engine.start() }

    // MARK: - Derived

    var context: MusicalContext { project.context }
    var melodyRowCount: Int { project.context.scale.degreeCount * 2 + 1 }
    var melodicLayers: [Layer] { project.layers.filter { $0.kind == .synth } }
    var drumLayers: [Layer] { project.layers.filter { $0.kind == .drum } }
    var editIndex: Int { project.currentPatternIndex }

    var selectedLayerId: UUID? { if case .track(let id) = selection { return id }; return nil }
    var selectedLayer: Layer? { selectedLayerId.flatMap { id in project.layers.first { $0.id == id } } }
    var selectedPatch: SynthPatch? { selectedLayer?.patch }

    var selectedMelody: [Int?] {
        guard let id = selectedLayerId else { return Array(repeating: nil, count: stepCount) }
        return project.patterns[editIndex].melody(id)
    }
    var otherMelodies: [[Int?]] {
        guard let sel = selectedLayerId else { return [] }
        return melodicLayers.filter { $0.id != sel }.map { project.patterns[editIndex].melody($0.id) }
    }
    func drumLane(_ id: UUID) -> [Bool] { project.patterns[editIndex].drumLane(id) }

    private func layer(_ id: UUID) -> Layer? { project.layers.first { $0.id == id } }
    private func layerIndex(_ id: UUID) -> Int? { project.layers.firstIndex { $0.id == id } }

    // MARK: - Transport

    func togglePlay() { isPlaying ? stop() : playPattern() }

    func playPattern() {
        engine.start(); engine.setSongMode(false); engine.setPattern(editIndex)
        engine.setPlaying(true); isPlaying = true; songPlaying = false; startPolling()
    }
    func playSong() {
        guard !project.song.isEmpty else { return }
        engine.start(); engine.setSong(project.song); engine.setSongMode(true)
        engine.setPlaying(true); isPlaying = true; songPlaying = true; startPolling()
    }
    func toggleSong() { isPlaying ? stop() : playSong() }

    func stop() {
        engine.setPlaying(false); isPlaying = false; songPlaying = false
        stopPolling(); currentStep = -1; playPosition = -1
    }
    func setTempo(_ bpm: Double) { tempo = min(max(bpm, 60), 200) }

    // MARK: - Layer management

    func addSynthLayer(_ patch: SynthPatch) {
        var l = Layer.synth(patch)
        l.engineId = engine.addTrack(kind: TrackKind.synth.rawValue, sound: 0)
        guard l.engineId >= 0 else { return }
        engine.setPatch(l.engineId, patch.toAB())
        project.layers.append(l)
        selection = .track(l.id)
    }

    /// Apply a patch to a synth layer (from the browser or the Sound Lab), live.
    func applyPatch(_ id: UUID, patch: SynthPatch) {
        guard let i = layerIndex(id), project.layers[i].kind == .synth else { return }
        project.layers[i].patch = patch
        engine.setPatch(project.layers[i].engineId, patch.toAB())
    }
    func addDrumLayer(_ sound: DrumSound) {
        var l = Layer.drum(sound)
        l.engineId = engine.addTrack(kind: TrackKind.drum.rawValue, sound: sound.rawValue)
        guard l.engineId >= 0 else { return }
        project.layers.append(l)
    }
    func removeTrack(_ id: UUID) {
        guard let i = layerIndex(id) else { return }
        engine.removeTrack(project.layers[i].engineId)
        let wasSel = selectedLayerId == id
        project.layers.remove(at: i)
        for p in project.patterns.indices { project.patterns[p].melodies[id] = nil; project.patterns[p].drums[id] = nil }
        if wasSel { selection = melodicLayers.last.map { .track($0.id) } ?? .drums }
    }
    func toggleMute(_ id: UUID) {
        guard let i = layerIndex(id) else { return }
        project.layers[i].muted.toggle()
        engine.setTrackMute(project.layers[i].engineId, muted: project.layers[i].muted)
    }
    func setTrackSound(_ id: UUID, sound: Int) {
        guard let i = layerIndex(id) else { return }
        project.layers[i].sound = sound
        engine.setTrackSound(project.layers[i].engineId, sound: sound)
    }
    func select(_ id: UUID) { selection = .track(id) }
    func selectDrums() { selection = .drums }

    // MARK: - Pattern management

    var patternNames: [String] { project.patterns.map(\.name) }

    func selectPattern(_ index: Int) {
        guard index >= 0, index < project.patterns.count else { return }
        project.currentPatternIndex = index
        engine.setPattern(index)
        objectWillChange.send()
    }
    func addPattern() {
        guard project.patterns.count < Project.maxPatterns else { return }
        let name = Project.patternNames[project.patterns.count]
        project.patterns.append(PatternData(name: name))
        selectPattern(project.patterns.count - 1)   // empty pattern already clear in engine
    }
    func duplicatePattern() {
        guard project.patterns.count < Project.maxPatterns else { return }
        var copy = project.patterns[editIndex]
        copy.id = UUID()
        copy.name = Project.patternNames[project.patterns.count]
        project.patterns.append(copy)
        let newIndex = project.patterns.count - 1
        project.currentPatternIndex = newIndex
        engine.setPattern(newIndex)
        pushPattern(newIndex)
    }

    // MARK: - Song management

    func appendSection(_ patternIndex: Int) {
        guard project.song.count < Int(AB_MAX_SONG_LEN) else { return }
        project.song.append(patternIndex)
        engine.setSong(project.song)
    }
    func removeSection(at i: Int) {
        guard i >= 0, i < project.song.count else { return }
        project.song.remove(at: i)
        engine.setSong(project.song)
        if project.song.isEmpty && songPlaying { stop() }
    }
    func clearSong() { project.song.removeAll(); engine.setSong(project.song); if songPlaying { stop() } }

    // MARK: - Editing: melody (selected synth layer, current pattern)

    func toggleMelody(row: Int, step: Int) {
        guard let l = selectedLayer, l.kind == .synth else { return }
        var lane = project.patterns[editIndex].melody(l.id)
        if lane[step] == row {
            lane[step] = nil
            engine.setStep(track: l.engineId, pattern: editIndex, step: step, note: 0, velocity: 0)
        } else {
            lane[step] = row
            let midi = context.midiNote(forRow: row)
            engine.setStep(track: l.engineId, pattern: editIndex, step: step, note: midi, velocity: l.melodyVelocity)
            engine.start(); engine.noteOn(track: l.engineId, note: midi, velocity: 0.9)
        }
        project.patterns[editIndex].melodies[l.id] = lane
    }
    func placeMelody(row: Int, step: Int) {
        guard let l = selectedLayer, l.kind == .synth else { return }
        var lane = project.patterns[editIndex].melody(l.id)
        guard lane[step] != row else { return }   // already there (paint dedupe)
        lane[step] = row
        project.patterns[editIndex].melodies[l.id] = lane
        engine.setStep(track: l.engineId, pattern: editIndex, step: step,
                       note: context.midiNote(forRow: row), velocity: l.melodyVelocity)
    }

    func clearMelodyStep(_ step: Int) {
        guard let l = selectedLayer, l.kind == .synth else { return }
        var lane = project.patterns[editIndex].melody(l.id)
        guard lane[step] != nil else { return }
        lane[step] = nil
        project.patterns[editIndex].melodies[l.id] = lane
        engine.setStep(track: l.engineId, pattern: editIndex, step: step, note: 0, velocity: 0)
    }

    /// Drag-paint a drum cell to an explicit on/off state (no toggle).
    func setDrum(_ id: UUID, step: Int, on: Bool) {
        guard let l = layer(id) else { return }
        var lane = project.patterns[editIndex].drumLane(id)
        guard lane[step] != on else { return }
        lane[step] = on
        project.patterns[editIndex].drums[id] = lane
        engine.setStep(track: l.engineId, pattern: editIndex, step: step, note: 0, velocity: on ? l.drumVelocity : 0)
    }

    /// Basic in-scale melody generator (placeholder for the future smart generator).
    /// A gentle random walk over scale degrees with rests, anchored to chord tones
    /// on strong beats. Freshly seeded per call, so every tap rerolls a new idea.
    func generateMelody() {
        guard let l = selectedLayer, l.kind == .synth else { return }
        let maxRow = melodyRowCount - 1
        var seed = UInt64.random(in: UInt64.min...UInt64.max) | 1
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(max(n, 1))) }

        let degrees = project.context.scale.degreeCount
        // Chord-tone rows (root and the ~fifth degree) in each visible octave.
        let fifthDegree = min(degrees - 1, 4)
        let anchors = [0, fifthDegree, degrees, degrees + fifthDegree, 2 * degrees].filter { $0 <= maxRow }

        var row = degrees // start at the middle-octave root
        var lane = [Int?](repeating: nil, count: stepCount)
        for s in 0..<stepCount {
            // Rest on some off-beats for phrasing.
            if s % 2 == 1 && rnd(100) < 45 { continue }
            let stepMove = [-2, -1, -1, 0, 1, 1, 2][rnd(7)]
            row = min(maxRow, max(0, row + stepMove))
            // Land on a nearby chord tone (root/fifth) on strong beats.
            if s % 8 == 0, let anchor = anchors.min(by: { abs($0 - row) < abs($1 - row) }) { row = anchor }
            lane[s] = row
        }
        project.patterns[editIndex].melodies[l.id] = lane
        // Push the whole lane.
        for s in 0..<stepCount {
            if let r = lane[s] {
                engine.setStep(track: l.engineId, pattern: editIndex, step: s, note: context.midiNote(forRow: r), velocity: l.melodyVelocity)
            } else {
                engine.setStep(track: l.engineId, pattern: editIndex, step: s, note: 0, velocity: 0)
            }
        }
    }
    func audition(row: Int) {
        guard let l = selectedLayer else { return }
        engine.start(); engine.noteOn(track: l.engineId, note: context.midiNote(forRow: row), velocity: 0.9)
    }
    func toggleRecord() { isRecording.toggle() }
    func highwayTap(row: Int) {
        audition(row: row)
        guard isRecording, isPlaying, playPosition >= 0 else { return }
        placeMelody(row: row, step: Int(playPosition.rounded()) % stepCount)
    }

    // MARK: - Editing: drums

    func toggleDrum(_ id: UUID, step: Int) {
        guard let l = layer(id) else { return }
        var lane = project.patterns[editIndex].drumLane(id)
        let on = !lane[step]
        lane[step] = on
        project.patterns[editIndex].drums[id] = lane
        engine.setStep(track: l.engineId, pattern: editIndex, step: step, note: 0, velocity: on ? l.drumVelocity : 0)
        if on { engine.start(); engine.noteOn(track: l.engineId, note: 0, velocity: Float(l.drumVelocity) / 127) }
    }

    // MARK: - Context + clear

    func setRoot(_ root: Int) { project.contextRoot = ((root % 12) + 12) % 12; repushAllMelodies() }
    func setScale(_ scale: Scale) {
        project.scaleRaw = scale.rawValue
        let maxRow = scale.degreeCount * 2
        for p in project.patterns.indices {
            for l in melodicLayers {
                if var lane = project.patterns[p].melodies[l.id] {
                    for s in lane.indices { if let r = lane[s], r > maxRow { lane[s] = maxRow } }
                    project.patterns[p].melodies[l.id] = lane
                }
            }
        }
        repushAllMelodies()
    }
    func clearCurrent() {
        switch selection {
        case .drums:
            for l in drumLayers {
                project.patterns[editIndex].drums[l.id] = Array(repeating: false, count: stepCount)
                engine.clearTrack(l.engineId, pattern: editIndex)
            }
        case .track(let id):
            guard let l = layer(id) else { return }
            project.patterns[editIndex].melodies[id] = Array(repeating: nil, count: stepCount)
            engine.clearTrack(l.engineId, pattern: editIndex)
        }
    }

    // MARK: - Engine sync

    private func pushEverything() { for p in project.patterns.indices { pushPattern(p) } }

    private func pushPattern(_ p: Int) {
        let ctx = project.context
        for l in project.layers {
            if l.kind == .drum {
                let lane = project.patterns[p].drumLane(l.id)
                for s in 0..<stepCount {
                    engine.setStep(track: l.engineId, pattern: p, step: s, note: 0, velocity: lane[s] ? l.drumVelocity : 0)
                }
            } else {
                let lane = project.patterns[p].melody(l.id)
                for s in 0..<stepCount {
                    if let row = lane[s] {
                        engine.setStep(track: l.engineId, pattern: p, step: s, note: ctx.midiNote(forRow: row), velocity: l.melodyVelocity)
                    } else {
                        engine.setStep(track: l.engineId, pattern: p, step: s, note: 0, velocity: 0)
                    }
                }
            }
        }
    }
    private func repushAllMelodies() {
        let ctx = project.context
        for p in project.patterns.indices {
            for l in melodicLayers {
                let lane = project.patterns[p].melody(l.id)
                for s in 0..<stepCount {
                    if let row = lane[s] {
                        engine.setStep(track: l.engineId, pattern: p, step: s, note: ctx.midiNote(forRow: row), velocity: l.melodyVelocity)
                    } else {
                        engine.setStep(track: l.engineId, pattern: p, step: s, note: 0, velocity: 0)
                    }
                }
            }
        }
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
        let p = engine.currentPattern
        if p != currentPattern { currentPattern = p }
        let sp = engine.songPosition
        if sp != songPosition { songPosition = sp }
    }
}
