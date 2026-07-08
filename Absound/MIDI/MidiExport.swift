//
//  MidiExport.swift
//  Builds a Type-1 .mid from the Project via AudioToolbox MusicSequence — one
//  track per layer, tempo track from the project, song sections laid out
//  bar-by-bar (or the current pattern when the arrangement is empty). Drum
//  layers use General MIDI percussion notes on channel 10, so the file drops
//  straight into Logic with sensible defaults.
//

import AudioToolbox
import Foundation

enum MidiExport {

    /// General MIDI percussion mapping (channel 10).
    private static func gmNote(_ d: DrumSound) -> UInt8 {
        switch d {
        case .kick: return 36      // Bass Drum 1
        case .snare: return 38     // Acoustic Snare
        case .hat: return 42       // Closed Hi-Hat
        case .openHat: return 46   // Open Hi-Hat
        case .clap: return 39      // Hand Clap
        case .tom: return 45       // Low Tom
        case .rim: return 37       // Side Stick
        case .perc: return 56      // Cowbell
        }
    }

    /// Renders the project to a .mid in the temp directory. Returns its URL.
    static func export(_ project: Project) -> URL? {
        var seq: MusicSequence?
        guard NewMusicSequence(&seq) == noErr, let sequence = seq else { return nil }
        defer { DisposeMusicSequence(sequence) }

        // Tempo track.
        var tempoTrack: MusicTrack?
        MusicSequenceGetTempoTrack(sequence, &tempoTrack)
        if let t = tempoTrack { MusicTrackNewExtendedTempoEvent(t, 0, project.tempo) }

        let ctx = project.context
        // The song's sections; a lone current pattern when the arrangement is empty.
        let sections: [Int] = project.song.isEmpty ? [project.currentPatternIndex] : project.song
        let sixteenth = 0.25              // beats
        let noteDur: Float32 = 0.23       // slightly detached 16ths

        var melodicChannel: UInt8 = 0
        for layer in project.layers {
            var track: MusicTrack?
            guard MusicSequenceNewTrack(sequence, &track) == noErr, let tr = track else { continue }

            let isDrum = layer.kind == .drum
            let channel: UInt8
            if isDrum {
                channel = 9   // GM percussion
            } else {
                channel = melodicChannel
                melodicChannel += 1
                if melodicChannel == 9 { melodicChannel = 10 }   // skip the drum channel
                if melodicChannel > 15 { melodicChannel = 15 }
            }

            for (si, patIdx) in sections.enumerated() {
                guard project.patterns.indices.contains(patIdx) else { continue }
                let pat = project.patterns[patIdx]
                let barStart = MusicTimeStamp(si * 4)   // 16 steps == 4 beats per section

                if isDrum {
                    let lane = pat.drumLane(layer.id)
                    let note = gmNote(DrumSound(rawValue: layer.sound) ?? .kick)
                    for s in 0..<Project.stepCount where lane[s] {
                        var msg = MIDINoteMessage(channel: channel, note: note,
                                                  velocity: UInt8(layer.drumVelocity),
                                                  releaseVelocity: 0, duration: 0.2)
                        MusicTrackNewMIDINoteEvent(tr, barStart + MusicTimeStamp(Double(s) * sixteenth), &msg)
                    }
                } else {
                    let lane = pat.melody(layer.id)
                    for s in 0..<Project.stepCount {
                        guard let row = lane[s] else { continue }
                        let midi = UInt8(clamping: ctx.midiNote(forRow: row))
                        var msg = MIDINoteMessage(channel: channel, note: midi,
                                                  velocity: UInt8(layer.melodyVelocity),
                                                  releaseVelocity: 0, duration: noteDur)
                        MusicTrackNewMIDINoteEvent(tr, barStart + MusicTimeStamp(Double(s) * sixteenth), &msg)
                    }
                }
            }
        }

        // Write the file, named after the song.
        let safe = project.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined().trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent((safe.isEmpty ? "Absound" : safe) + ".mid")
        try? FileManager.default.removeItem(at: url)
        let status = MusicSequenceFileCreate(sequence, url as CFURL, .midiType, .eraseFile, 0)
        return status == noErr ? url : nil
    }
}
