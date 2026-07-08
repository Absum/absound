//
//  SongLibrary.swift
//  Saved songs, persisted as JSON in Documents. The working copy still lives in
//  project.json (autosaved); the library holds named snapshots you can return to.
//

import Foundation

@MainActor
final class SongLibrary: ObservableObject {
    @Published private(set) var songs: [Project] = []

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("songs.json")
        load()
    }

    /// Insert or update (by id).
    func save(_ project: Project) {
        if let i = songs.firstIndex(where: { $0.id == project.id }) {
            songs[i] = project
        } else {
            songs.append(project)
        }
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = songs.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        songs[i].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        songs.removeAll { $0.id == id }
        persist()
    }

    func contains(_ id: UUID) -> Bool { songs.contains { $0.id == id } }

    func uniqueName(_ base: String) -> String {
        let existing = Set(songs.map(\.name))
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let stored = try? JSONDecoder().decode([Project].self, from: data) else { return }
        songs = stored
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(songs) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
