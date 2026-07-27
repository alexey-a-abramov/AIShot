import Foundation

/// A human note plus an optional project tag attached to a saved capture.
/// Stored alongside (or apart from) the images — not baked into the pixels.
public struct CaptureMetadata: Codable, Sendable, Equatable {
    public var note: String
    /// The project/name tag, or `nil` when untagged.
    public var tag: String?
    public var updatedAt: Date

    public init(note: String = "", tag: String? = nil, updatedAt: Date = Date()) {
        self.note = note
        self.tag = tag
        self.updatedAt = updatedAt
    }

    /// Whether there's anything worth persisting (empty note + no tag is a no-op).
    public var isEmpty: Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (tag?.isEmpty ?? true)
    }
}

/// The on-disk index: maps a capture's key (its file name, or its absolute path
/// for a shared database) to its `CaptureMetadata`.
public struct CaptureMetadataIndex: Codable, Sendable, Equatable {
    public var version: Int
    public var items: [String: CaptureMetadata]

    public init(version: Int = 1, items: [String: CaptureMetadata] = [:]) {
        self.version = version
        self.items = items
    }

    /// Distinct, non-empty tags, sorted case-insensitively.
    public var tags: [String] {
        let unique = Set(items.values.compactMap(\.tag).filter { !$0.isEmpty })
        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// Reads and writes a capture-metadata index JSON file at an arbitrary location.
/// The *where* (a hidden dotfile beside the images, a visible file, or a shared
/// database in a custom folder) is decided by the caller — this store just
/// operates on a given index URL and entry key. Serialized through an actor;
/// each index file is cached and invalidated on write.
public actor CaptureMetadataStore {
    /// Default visible index file name.
    public static let visibleFileName = "aishot-metadata.json"
    /// Default hidden (dot-prefixed) index file name.
    public static let hiddenFileName = ".aishot-metadata.json"

    private var cache: [URL: CaptureMetadataIndex] = [:]

    public init() {}

    // MARK: - Reads

    /// The full index stored at `url` (empty if the file doesn't exist yet).
    public func index(at url: URL) -> CaptureMetadataIndex {
        let key = url.standardizedFileURL
        if let cached = cache[key] { return cached }
        let index = loadIndex(at: key)
        cache[key] = index
        return index
    }

    /// Reads an index straight from disk, bypassing the cache.
    private func loadIndex(at url: URL) -> CaptureMetadataIndex {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? Self.decoder.decode(CaptureMetadataIndex.self, from: data)
        else { return CaptureMetadataIndex() }
        return decoded
    }

    public func metadata(at url: URL, key: String) -> CaptureMetadata? {
        index(at: url).items[key]
    }

    public func tags(at url: URL) -> [String] {
        index(at: url).tags
    }

    // MARK: - Writes

    /// Inserts or replaces the metadata for `key`. An empty note + empty tag
    /// removes the entry instead of storing a blank one. Returns the stored
    /// metadata (or `nil` if it was a removal).
    @discardableResult
    public func upsert(at url: URL, key: String, note: String, tag: String?) throws -> CaptureMetadata? {
        let standardized = url.standardizedFileURL
        var index = index(at: standardized)

        let cleanTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let meta = CaptureMetadata(
            note: note,
            tag: (cleanTag?.isEmpty == false) ? cleanTag : nil
        )

        // Clearing an entry that was never there is a no-op — don't create an
        // index file in a folder that has no metadata (e.g. trashing an
        // untagged capture would otherwise litter one into its folder).
        guard !meta.isEmpty || index.items[key] != nil else { return nil }

        if meta.isEmpty {
            index.items[key] = nil
        } else {
            index.items[key] = meta
        }
        try persist(index, to: standardized)
        return meta.isEmpty ? nil : meta
    }

    /// Moves an index file from `oldURL` to `newURL` (used when the user changes
    /// the database location). No-op if the source is missing or identical.
    /// If a target already exists, the two indexes are **merged** (newer entry
    /// wins per key) so no notes are lost.
    public func move(from oldURL: URL, to newURL: URL) {
        let old = oldURL.standardizedFileURL
        let new = newURL.standardizedFileURL
        guard old != new, FileManager.default.fileExists(atPath: old.path) else { return }
        try? FileManager.default.createDirectory(
            at: new.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: new.path) {
            let source = loadIndex(at: old)
            var target = loadIndex(at: new)
            for (key, meta) in source.items {
                if let existing = target.items[key], existing.updatedAt >= meta.updatedAt { continue }
                target.items[key] = meta
            }
            try? persist(target, to: new)
            try? FileManager.default.removeItem(at: old)
        } else {
            try? FileManager.default.moveItem(at: old, to: new)
            applyHiddenFlag(new)
        }
        cache[old] = nil
        cache[new] = nil
    }

    // MARK: - Internals

    private func persist(_ index: CaptureMetadataIndex, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(index)
        try data.write(to: url, options: .atomic)
        applyHiddenFlag(url)
        cache[url] = index
    }

    /// Set the macOS hidden flag for dot-prefixed index files (belt-and-braces
    /// on top of the leading-dot convention).
    private func applyHiddenFlag(_ url: URL) {
        guard url.lastPathComponent.hasPrefix(".") else { return }
        var values = URLResourceValues()
        values.isHidden = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
