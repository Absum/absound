//
//  AudioEngine.swift
//  Owns the AVAudioEngine graph and the C++ DSP core. A stereo AVAudioSourceNode
//  pulls audio straight from ab_core_render on the realtime thread — the engine's
//  internal sequencer keeps timing locked to the audio clock.
//

import AVFoundation
import Foundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private var core: OpaquePointer?
    private(set) var sampleRate: Double = 44_100
    private var running = false

    init() {
        configureSession()
        // Build the core at the hardware sample rate to avoid resampling.
        sampleRate = AVAudioSession.sharedInstance().sampleRate
        if sampleRate < 8_000 { sampleRate = 44_100 }
        core = ab_core_create(sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let coreRef = core
        sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let lData = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let rData = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            ab_core_render(coreRef, lData, rData, Int32(frameCount))
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    deinit {
        engine.stop()
        if let core { ab_core_destroy(core) }
    }

    // MARK: - Session / lifecycle

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setPreferredSampleRate(44_100)
        try? session.setActive(true)
    }

    func start() {
        guard !running else { return }
        do { try engine.start(); running = true }
        catch { print("AudioEngine start failed: \(error)") }
    }

    func stop() {
        engine.stop()
        running = false
    }

    // MARK: - Transport / pattern passthrough

    func setTempo(_ bpm: Double) { ab_core_set_tempo(core, bpm) }
    func setPlaying(_ playing: Bool) { ab_core_set_playing(core, playing ? 1 : 0) }
    var currentStep: Int { Int(ab_core_current_step(core)) }
    var playPosition: Double { ab_core_play_position(core) }
    var currentPattern: Int { Int(ab_core_current_pattern(core)) }
    var songPosition: Int { Int(ab_core_song_position(core)) }

    // Track pool.
    @discardableResult
    func addTrack(kind: Int, sound: Int) -> Int { Int(ab_core_add_track(core, Int32(kind), Int32(sound))) }
    func removeTrack(_ engineId: Int) { ab_core_remove_track(core, Int32(engineId)) }
    func setTrackSound(_ engineId: Int, sound: Int) { ab_core_set_track_sound(core, Int32(engineId), Int32(sound)) }
    func setTrackMute(_ engineId: Int, muted: Bool) { ab_core_set_track_mute(core, Int32(engineId), muted ? 1 : 0) }
    func clearTrack(_ engineId: Int, pattern: Int) { ab_core_clear_track(core, Int32(engineId), Int32(pattern)) }

    func setStep(track: Int, pattern: Int, step: Int, note: Int, velocity: Int) {
        ab_core_set_step(core, Int32(track), Int32(pattern), Int32(step), Int32(note), Int32(velocity))
    }
    func noteOn(track: Int, note: Int, velocity: Float) {
        ab_core_note_on(core, Int32(track), Int32(note), velocity)
    }

    // Patterns & song.
    func setPattern(_ index: Int) { ab_core_set_pattern(core, Int32(index)) }
    func setSongMode(_ on: Bool) { ab_core_set_song_mode(core, on ? 1 : 0) }
    func setSong(_ seq: [Int]) {
        var s = seq.map { Int32($0) }
        ab_core_set_song(core, &s, Int32(s.count))
    }
}
