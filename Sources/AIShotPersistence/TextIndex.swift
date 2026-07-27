import Foundation

/// OCR'd text for one capture, plus the fingerprint of the file it came from
/// so it can be re-indexed when the file changes.
public struct CaptureText: Codable, Sendable, Equatable {
    public var text: String
    /// File size at index time — cheap change detection alongside `modifiedAt`.
    public var fileSize: Int
    public var modifiedAt: Date
    public var indexedAt: Date

    public init(text: String, fileSize: Int, modifiedAt: Date, indexedAt: Date = Date()) {
        self.text = text
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.indexedAt = indexedAt
    }
}

/// The on-disk full-text index: capture path → recognized text.
public struct CaptureTextIndex: Codable, Sendable, Equatable {
    public var version: Int
    /// Keyed by standardized absolute file path.
    public var items: [String: CaptureText]

    public init(version: Int = 1, items: [String: CaptureText] = [:]) {
        self.version = version
        self.items = items
    }
}

/// Stores OCR'd text for captures so every screenshot becomes searchable.
///
/// Deliberately **separate from `CaptureMetadataStore`**: that index is loaded
/// wholesale and atomically rewritten on every note/tag edit, so putting
/// megabytes of recognized text in it would make tagging progressively slower.
/// This is also derived data — it lives in the app's own support directory, not
/// beside the user's images, and can be deleted and rebuilt at any time.
public actor CaptureTextIndexStore {
    private let url: URL
    private var cache: CaptureTextIndex?
    /// Coalesces the burst of writes that happens while indexing a backlog.
    private var dirty = false
    private var flushTask: Task<Void, Never>?

    public init(fileURL: URL) {
        self.url = fileURL
    }

    // MARK: - Reads

    public func text(for fileURL: URL) -> CaptureText? {
        load().items[Self.key(fileURL)]
    }

    public func allText() -> [String: CaptureText] {
        load().items
    }

    /// Whether `fileURL` still needs indexing — true when it was never indexed,
    /// or when the file changed since it was.
    public func needsIndexing(_ fileURL: URL) -> Bool {
        guard let existing = load().items[Self.key(fileURL)] else { return true }
        guard let stamp = Self.fingerprint(fileURL) else { return false } // gone; nothing to do
        return existing.fileSize != stamp.size || existing.modifiedAt != stamp.modified
    }

    /// Captures whose recognized text contains `query` (case- and
    /// diacritic-insensitive), newest-indexed first.
    public func search(_ query: String) -> [(url: URL, snippet: String)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return load().items
            .filter {
                $0.value.text.range(
                    of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
            .sorted { $0.value.indexedAt > $1.value.indexedAt }
            .map { (URL(fileURLWithPath: $0.key), Self.snippet(of: $0.value.text, around: trimmed)) }
    }

    // MARK: - Writes

    /// Records recognized text for a capture.
    public func store(text: String, for fileURL: URL) {
        guard let stamp = Self.fingerprint(fileURL) else { return }
        var index = load()
        index.items[Self.key(fileURL)] = CaptureText(
            text: text, fileSize: stamp.size, modifiedAt: stamp.modified
        )
        cache = index
        scheduleFlush()
    }

    public func remove(_ fileURL: URL) {
        var index = load()
        guard index.items.removeValue(forKey: Self.key(fileURL)) != nil else { return }
        cache = index
        scheduleFlush()
    }

    /// Drops entries whose files no longer exist, so the index doesn't grow
    /// forever. Returns how many were pruned.
    @discardableResult
    public func pruneMissing() -> Int {
        var index = load()
        let before = index.items.count
        index.items = index.items.filter { FileManager.default.fileExists(atPath: $0.key) }
        guard index.items.count != before else { return 0 }
        cache = index
        scheduleFlush()
        return before - index.items.count
    }

    /// Writes any pending changes immediately (call before the app exits).
    public func flush() {
        flushTask?.cancel()
        flushTask = nil
        persist()
    }

    // MARK: - Internals

    /// Batches writes: indexing a backlog would otherwise rewrite the whole
    /// file once per capture.
    ///
    /// This is a **max-delay** debounce, not a resettable one. Resetting the
    /// timer on every write meant that during a backlog — where each OCR
    /// finishes well inside the window — the timer was always re-armed and
    /// nothing ever reached disk until the very end, so quitting mid-run lost
    /// every result and re-OCR'd them next launch.
    private func scheduleFlush() {
        dirty = true
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    private func persist() {
        flushTask = nil
        guard dirty, let index = cache else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let data = try? Self.encoder.encode(index) else { return }
        do {
            try data.write(to: url, options: .atomic)
            // Only clear the flag once the bytes are actually on disk, so a
            // failed write is retried by the next flush rather than dropped.
            dirty = false
        } catch {
            // Leave `dirty` set; the cache still holds the data.
        }
    }

    private func load() -> CaptureTextIndex {
        if let cache { return cache }
        let index: CaptureTextIndex
        if let data = try? Data(contentsOf: url),
           let decoded = try? Self.decoder.decode(CaptureTextIndex.self, from: data) {
            index = decoded
        } else {
            index = CaptureTextIndex()
        }
        cache = index
        return index
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// Reads size + mtime through `FileManager`, **not** `URL.resourceValues`:
    /// a `URL` caches resource values on the instance, so re-reading one that
    /// was already stat'd returns the old size and the file never looks changed.
    private static func fingerprint(_ url: URL) -> (size: Int, modified: Date)? {
        guard let attributes = try? FileManager.default
            .attributesOfItem(atPath: url.standardizedFileURL.path),
            let size = attributes[.size] as? Int,
            let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return (size, modified)
    }

    /// A short excerpt around the first match, for showing why a result matched.
    static func snippet(of text: String, around query: String, radius: Int = 60) -> String {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(radius * 2))
        }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex)
            ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex)
            ?? text.endIndex
        var snippet = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        return snippet.trimmingCharacters(in: .whitespaces)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
