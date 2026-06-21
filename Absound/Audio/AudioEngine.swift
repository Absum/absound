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

    func setStep(track: Int32, step: Int, note: Int, velocity: Int) {
        ab_core_set_step(core, track, Int32(step), Int32(note), Int32(velocity))
    }
    func clear() { ab_core_clear(core) }
    func noteOn(track: Int32, note: Int, velocity: Float) {
        ab_core_note_on(core, track, Int32(note), velocity)
    }
}
