//
//  ProjectStore.swift
//  Persists the whole Project (layers + patches, patterns, song, tempo, key) as
//  JSON in Documents. TransportController autosaves through this on every edit
//  (debounced) and on backgrounding; load() runs at launch.
//

import Foundation

struct ProjectStore {
    let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("project.json")
    }

    func load() -> Project? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(Project.self, from: data)
    }

    func save(_ project: Project) {
        guard let data = try? JSONEncoder().encode(project) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
