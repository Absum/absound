//
//  ProjectStoreTests.swift
//  Project persistence: everything a song is made of survives a reload, and the
//  stale engine handle does not.
//

import XCTest

final class ProjectStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("project-test-\(UUID().uuidString).json")
    }

    func testFullProjectRoundTrip() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var p = Project.demo()
        p.tempo = 137
        p.contextRoot = 3
        p.scaleRaw = Scale.dorian.rawValue
        p.song = [0, 0, 0]
        // A custom user sound on the lead layer + a melody edit.
        let leadIdx = p.layers.lastIndex { $0.kind == .synth }!
        var custom = PatchFactory.named("Laser")
        custom.id = UUID(); custom.isFactory = false; custom.name = "My Laser"
        custom.cutoff = 4321
        p.layers[leadIdx].patch = custom
        p.layers[leadIdx].engineId = 7   // stale runtime handle — must NOT persist
        p.patterns[0].melodies[p.layers[leadIdx].id]?[5] = 9

        let store = ProjectStore(storageURL: url)
        store.save(p)
        guard let loaded = ProjectStore(storageURL: url).load() else {
            return XCTFail("project failed to load")
        }

        XCTAssertEqual(loaded.tempo, 137)
        XCTAssertEqual(loaded.contextRoot, 3)
        XCTAssertEqual(loaded.scaleRaw, Scale.dorian.rawValue)
        XCTAssertEqual(loaded.song, [0, 0, 0])
        XCTAssertEqual(loaded.layers.count, p.layers.count)

        let lead = loaded.layers[leadIdx]
        XCTAssertEqual(lead.patch?.name, "My Laser")
        XCTAssertEqual(lead.patch?.cutoff, 4321)
        XCTAssertEqual(lead.engineId, -1, "stale engine handle must not persist")
        XCTAssertEqual(loaded.patterns[0].melodies[lead.id]?[5], 9, "melody edits survive")
        XCTAssertEqual(loaded.patterns[0].drumLane(loaded.layers[0].id),
                       p.patterns[0].drumLane(p.layers[0].id), "drum lanes survive")
    }

    func testMissingFileYieldsNil() {
        XCTAssertNil(ProjectStore(storageURL: tempURL()).load())
    }
}
