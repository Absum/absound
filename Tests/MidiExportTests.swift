//
//  MidiExportTests.swift
//  Export the demo project and reload the .mid to verify structure.
//

import AudioToolbox
import XCTest

final class MidiExportTests: XCTestCase {

    func testExportProducesLoadableMidiWithAllTracks() throws {
        var project = Project.demo()
        project.name = "Test Song"
        project.song = [0, 0]   // two sections

        let url = try XCTUnwrap(MidiExport.export(project), "export must produce a file")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "Test Song.mid")

        var seq: MusicSequence?
        NewMusicSequence(&seq)
        let sequence = try XCTUnwrap(seq)
        defer { DisposeMusicSequence(sequence) }
        XCTAssertEqual(MusicSequenceFileLoad(sequence, url as CFURL, .midiType, []), noErr,
                       "exported file must load back as MIDI")

        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)
        // One track per layer (5 in the demo). (Loaders may or may not surface the
        // tempo track in the count; require at least the layer tracks.)
        XCTAssertGreaterThanOrEqual(Int(trackCount), project.layers.count)

        // The lead layer has 7 notes per section x 2 sections = 14 events.
        // Find a track with exactly 14 note events.
        var found14 = false
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, i, &track)
            guard let tr = track else { continue }
            var iterator: MusicEventIterator?
            NewMusicEventIterator(tr, &iterator)
            guard let it = iterator else { continue }
            defer { DisposeMusicEventIterator(it) }
            var notes = 0
            var hasEvent: DarwinBoolean = false
            MusicEventIteratorHasCurrentEvent(it, &hasEvent)
            while hasEvent.boolValue {
                var ts = MusicTimeStamp(0); var type = MusicEventType(0)
                var data: UnsafeRawPointer?; var size = UInt32(0)
                MusicEventIteratorGetEventInfo(it, &ts, &type, &data, &size)
                if type == kMusicEventType_MIDINoteMessage { notes += 1 }
                MusicEventIteratorNextEvent(it)
                MusicEventIteratorHasCurrentEvent(it, &hasEvent)
            }
            if notes == 14 { found14 = true }
        }
        XCTAssertTrue(found14, "lead track must carry 7 notes x 2 sections")
    }

    func testEmptySongExportsCurrentPattern() throws {
        var project = Project.demo()
        project.song = []   // no arrangement -> current pattern once
        let url = try XCTUnwrap(MidiExport.export(project))
        defer { try? FileManager.default.removeItem(at: url) }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size ?? 0, 100, "single-pattern export still writes real content")
    }
}
