import Foundation
import AIShotCore

/// `UserDefaults`-backed settings persistence (Codable JSON under one key).
public struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "settings.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return .default }
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}

/// JSON-file-backed capture history (newest first), serialized through an actor.
public actor FileHistoryStore: HistoryStore {
    private let url: URL
    private var cache: [HistoryEntry]?

    public init(fileURL: URL) {
        self.url = fileURL
    }

    public func record(_ entry: HistoryEntry) async throws {
        var entries = try loadAll()
        entries.insert(entry, at: 0)
        try persist(entries)
    }

    public func recent(limit: Int) async throws -> [HistoryEntry] {
        Array(try loadAll().prefix(max(0, limit)))
    }

    public func remove(ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }
        var entries = try loadAll()
        let remaining = entries.filter { !ids.contains($0.id) }
        guard remaining.count != entries.count else { return } // nothing matched
        entries = remaining
        try persist(entries) // also refreshes the in-memory cache
    }

    private func loadAll() throws -> [HistoryEntry] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: url.path) else {
            cache = []
            return []
        }
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        cache = entries
        return entries
    }

    private func persist(_ entries: [HistoryEntry]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url, options: .atomic)
        cache = entries
    }
}
