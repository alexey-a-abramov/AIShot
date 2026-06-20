import Foundation

/// A human note plus an optional project tag attached to a saved capture.
/// Stored alongside the images (not baked into the pixels).
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

/// The on-disk index written to `aishot-metadata.json` in a capture directory:
/// maps each capture's file name to its `CaptureMetadata`.
public struct CaptureMetadataIndex: Codable, Sendable, Equatable {
    public var version: Int
    /// Keyed by file name (e.g. `"AIShot 2026-06-20 at 12.00.00.png"`).
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

/// Reads and writes per-directory `aishot-metadata.json` files. Serialized
/// through an actor; each directory's index is cached and invalidated on write.
///
/// The metadata lives in the same folder as the images so it's human-readable
/// and travels with a backup of the screenshots folder.
public actor CaptureMetadataStore {
    /// The sidecar index file name placed in each capture directory.
    public static let fileName = "aishot-metadata.json"

    private var cache: [URL: CaptureMetadataIndex] = [:]

    public init() {}

    // MARK: - Reads

    /// The full index for a directory (empty if none exists yet).
    public func index(for directory: URL) -> CaptureMetadataIndex {
        let dir = directory.standardizedFileURL
        if let cached = cache[dir] { return cached }
        let index: CaptureMetadataIndex
        if let data = try? Data(contentsOf: fileURL(for: dir)),
           let decoded = try? Self.decoder.decode(CaptureMetadataIndex.self, from: data) {
            index = decoded
        } else {
            index = CaptureMetadataIndex()
        }
        cache[dir] = index
        return index
    }

    public func metadata(directory: URL, fileName: String) -> CaptureMetadata? {
        index(for: directory).items[fileName]
    }

    public func tags(for directory: URL) -> [String] {
        index(for: directory).tags
    }

    // MARK: - Writes

    /// Inserts or replaces the metadata for `fileName`. An empty note + empty
    /// tag removes the entry instead of storing a blank one. Returns the stored
    /// metadata (or `nil` if it was a removal).
    @discardableResult
    public func upsert(directory: URL, fileName: String, note: String, tag: String?) throws -> CaptureMetadata? {
        let dir = directory.standardizedFileURL
        var index = index(for: dir)

        let cleanTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let meta = CaptureMetadata(
            note: note,
            tag: (cleanTag?.isEmpty == false) ? cleanTag : nil
        )

        if meta.isEmpty {
            index.items[fileName] = nil
        } else {
            index.items[fileName] = meta
        }
        try persist(index, to: dir)
        return meta.isEmpty ? nil : meta
    }

    // MARK: - Internals

    private func fileURL(for directory: URL) -> URL {
        directory.appendingPathComponent(Self.fileName)
    }

    private func persist(_ index: CaptureMetadataIndex, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(index)
        try data.write(to: fileURL(for: directory), options: .atomic)
        cache[directory] = index
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
