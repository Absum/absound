//
//  PatchLibrary.swift
//  The user's saved sounds ("My Sounds"), persisted as JSON in Documents and
//  loaded at launch. Factory presets live in PatchFactory; saving a factory
//  patch copies it here with a fresh id. Layers embed their patch value, so
//  deleting a library entry never breaks a project.
//

import Foundation

@MainActor
final class PatchLibrary: ObservableObject {
    @Published private(set) var userPatches: [SynthPatch] = []

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("patches.json")
        load()
    }

    // MARK: - CRUD

    /// Insert or update (by id). Returns the stored patch.
    @discardableResult
    func save(_ patch: SynthPatch) -> SynthPatch {
        var p = patch
        p.isFactory = false
        if let i = userPatches.firstIndex(where: { $0.id == p.id }) {
            userPatches[i] = p
        } else {
            userPatches.append(p)
        }
        persist()
        return p
    }

    /// Copy a (factory or user) patch into My Sounds under a unique name and new id.
    /// Pass `named` to choose the name ("Save as…"); it is still uniqued.
    @discardableResult
    func saveAsCopy(of patch: SynthPatch, named: String? = nil) -> SynthPatch {
        var p = patch
        p.id = UUID()
        p.isFactory = false
        let base = named?.trimmingCharacters(in: .whitespacesAndNewlines)
        p.name = uniqueName((base?.isEmpty == false ? base! : p.name))
        userPatches.append(p)
        persist()
        return p
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = userPatches.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userPatches[i].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        userPatches.removeAll { $0.id == id }
        persist()
    }

    func contains(_ id: UUID) -> Bool { userPatches.contains { $0.id == id } }

    private func uniqueName(_ base: String) -> String {
        let existing = Set(userPatches.map(\.name) + PatchFactory.presets.map(\.name))
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let patches = try? JSONDecoder().decode([SynthPatch].self, from: data) else { return }
        userPatches = patches
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(userPatches) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
