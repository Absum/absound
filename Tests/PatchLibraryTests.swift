//
//  PatchLibraryTests.swift
//  My Sounds persistence: save/rename/delete survive a reload from disk.
//

import XCTest

@MainActor
final class PatchLibraryTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("patches-test-\(UUID().uuidString).json")
    }

    func testSaveAsCopyPersistsAcrossReload() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let lib = PatchLibrary(storageURL: url)
        XCTAssertTrue(lib.userPatches.isEmpty)

        let saved = lib.saveAsCopy(of: PatchFactory.named("Super Saw"))
        XCTAssertFalse(saved.isFactory)
        XCTAssertNotEqual(saved.id, PatchFactory.named("Super Saw").id)
        XCTAssertEqual(saved.name, "Super Saw 2", "name must be uniquified against the factory list")

        // Fresh instance = app relaunch.
        let reloaded = PatchLibrary(storageURL: url)
        XCTAssertEqual(reloaded.userPatches.count, 1)
        XCTAssertEqual(reloaded.userPatches.first?.name, "Super Saw 2")
        XCTAssertEqual(reloaded.userPatches.first?.unison, 7, "patch fields must round-trip")
    }

    func testSaveUpdatesInPlaceAndRenameAndDelete() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let lib = PatchLibrary(storageURL: url)
        var p = lib.saveAsCopy(of: PatchFactory.named("Deep Sub"))
        p.cutoff = 555
        lib.save(p)
        XCTAssertEqual(lib.userPatches.count, 1, "save by same id must update, not duplicate")
        XCTAssertEqual(lib.userPatches.first?.cutoff, 555)

        lib.rename(p.id, to: "Mega Bass")
        XCTAssertEqual(PatchLibrary(storageURL: url).userPatches.first?.name, "Mega Bass")

        lib.delete(p.id)
        XCTAssertTrue(PatchLibrary(storageURL: url).userPatches.isEmpty)
    }
}
