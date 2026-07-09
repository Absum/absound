//
//  AudioEngine.swift
//  Owns the AVAudioEngine graph and the C++ DSP core. A stereo AVAudioSourceNode
//  pulls audio straight from ab_core_render on the realtime thread — the engine's
//  internal sequencer keeps timing locked to the audio clock.
//
//  Resilience: init touches NO CoreAudio (a wedged audio daemon — Mac sleep,
//  phone call, media-services crash — must never block or kill launch). The
//  graph is built and started asynchronously on a serial queue; AVAudioSession
//  interruptions, route changes, media-services resets, and app foregrounding
//  all reconcile the engine back to the app's intent (`wantRunning`).
//

import AVFoundation
import UIKit

final class AudioEngine {
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var core: OpaquePointer?
    /// The core runs at a fixed rate; AVAudioEngine sample-rate-converts to the
    /// hardware, so we never need to ask CoreAudio anything before first render.
    private(set) var sampleRate: Double = 48_000
    /// Intent — what the app *wants*. `engine.isRunning` is the truth; the two
    /// are reconciled after every lifecycle event.
    private var wantRunning = false
    private var graphBuilt = false
    private let audioQueue = DispatchQueue(label: "fi.absum.absound.audio", qos: .userInitiated)

    init() {
        core = ab_core_create(sampleRate)
        observeLifecycle()
    }

    deinit {
        engine.stop()
        if let core { ab_core_destroy(core) }
    }

    // MARK: - Bring-up / lifecycle

    func start() {
        wantRunning = true
        audioQueue.async { [weak self] in self?.startLocked() }
    }

    func stop() {
        wantRunning = false
        audioQueue.async { [weak self] in self?.engine.stop() }
    }

    /// Build the graph (once) and start the engine if the app wants audio.
    /// Runs on `audioQueue` only.
    private func startLocked() {
        buildGraphLocked()
        guard wantRunning, graphBuilt, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            // Transient failures (session not yet active after an interruption)
            // usually clear in well under a second — retry once, then leave it
            // to the next lifecycle reconcile.
            audioQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.wantRunning, self.graphBuilt, !self.engine.isRunning else { return }
                try? self.engine.start()
            }
        }
    }

    private func buildGraphLocked() {
        guard !graphBuilt else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setPreferredSampleRate(sampleRate)
        try? session.setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let coreRef = core
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let lData = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let rData = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            ab_core_render(coreRef, lData, rData, Int32(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        sourceNode = node
        graphBuilt = true
    }

    /// Bring reality back in line with intent after any lifecycle event.
    private func reconcile() {
        audioQueue.async { [weak self] in
            guard let self, self.wantRunning else { return }
            self.startLocked()
        }
    }

    /// Media services died and came back: every audio object we held is junk.
    /// Rebuild the whole graph from scratch.
    private func rebuildAfterReset() {
        engine.stop()
        engine = AVAudioEngine()
        sourceNode = nil
        graphBuilt = false
        if wantRunning { startLocked() }
    }

    private func observeLifecycle() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended {
                let raw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if AVAudioSession.InterruptionOptions(rawValue: raw).contains(.shouldResume) {
                    self.reconcile()
                }
            }
            // .began: the system already paused us; intent is unchanged, so the
            // next reconcile (interruption end / foreground) restarts cleanly.
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.reconcile()   // headphones out, AirPods in — engine often stops
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
            self?.reconcile()
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.audioQueue.async { self.rebuildAfterReset() }
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.reconcile()
        }
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
    func setPatch(_ engineId: Int, _ patch: ABPatch) {
        var p = patch
        ab_core_set_patch(core, Int32(engineId), &p)
    }
    func setFX(_ engineId: Int, _ chain: ABFXChain) {
        var c = chain
        ab_core_set_fx(core, Int32(engineId), &c)
    }
    func setMasterFX(_ chain: ABFXChain) {
        var c = chain
        ab_core_set_master_fx(core, &c)
    }
    func setStrip(_ engineId: Int, gain: Float, pan: Float, delaySend: Float, reverbSend: Float) {
        ab_core_set_track_strip(core, Int32(engineId), gain, pan, delaySend, reverbSend)
    }
    func trackLevel(_ engineId: Int) -> Float { ab_core_track_level(core, Int32(engineId)) }
    var masterLevel: Float { ab_core_master_level(core) }
    func setTrackMute(_ engineId: Int, muted: Bool) { ab_core_set_track_mute(core, Int32(engineId), muted ? 1 : 0) }
    func setTrackSolo(_ engineId: Int, soloed: Bool) { ab_core_set_track_solo(core, Int32(engineId), soloed ? 1 : 0) }
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
