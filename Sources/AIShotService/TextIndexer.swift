import Foundation
import AIShotAutomation
import AIShotCore
import AIShotPersistence

/// Builds and maintains the full-text index over captures, so every screenshot
/// becomes searchable by the words *inside* it — for the Dashboard's search box
/// and for agents over MCP.
///
/// Runs opportunistically in the background: it only OCRs captures that were
/// never indexed or whose file changed, one at a time at low priority, so it
/// never competes with an in-progress capture.
public actor TextIndexer {
    private let store: CaptureTextIndexStore
    private let recognizer = TextRecognizer()
    private var running: Task<Int, Never>?

    public init(store: CaptureTextIndexStore) {
        self.store = store
    }

    /// Indexes any of `entries` that need it. Returns the number newly indexed.
    /// Concurrent calls share the in-flight run rather than double-indexing.
    @discardableResult
    public func index(_ entries: [HistoryEntry]) async -> Int {
        if let running { return await running.value }

        let candidates = entries.compactMap { entry -> URL? in
            // Videos have no text to recognize.
            guard entry.kind == .image, let url = entry.fileURL else { return nil }
            return url
        }
        guard !candidates.isEmpty else { return 0 }

        let task = Task<Int, Never>(priority: .utility) { [store, recognizer] in
            var indexed = 0
            for url in candidates {
                if Task.isCancelled { break }
                guard await store.needsIndexing(url) else { continue }
                // Read off this actor: a multi-MB PNG read would otherwise
                // block concurrent search()/forget() calls.
                guard let data = await Task.detached(priority: .utility, operation: {
                    FileManager.default.fileExists(atPath: url.path)
                        ? try? Data(contentsOf: url) : nil
                }).value else { continue }

                do {
                    // An image with genuinely no text stores "" so it isn't
                    // retried forever; a *thrown* error is left unindexed so a
                    // transient failure gets another chance next run.
                    let text = try await recognizer.recognizeText(in: data)
                    await store.store(text: text, for: url)
                    indexed += 1
                } catch {
                    continue
                }
            }
            await store.flush()
            return indexed
        }
        running = task
        let count = await task.value
        running = nil
        return count
    }

    /// Captures whose recognized text matches `query`.
    public func search(_ query: String) async -> [TextSearchHit] {
        await store.search(query).map { TextSearchHit(fileURL: $0.url, snippet: $0.snippet) }
    }

    /// Recognized text for one capture, if it's been indexed.
    public func text(for fileURL: URL) async -> String? {
        await store.text(for: fileURL)?.text
    }

    /// Drops index entries whose files are gone.
    @discardableResult
    public func pruneMissing() async -> Int {
        let pruned = await store.pruneMissing()
        if pruned > 0 { await store.flush() }
        return pruned
    }

    public func forget(_ fileURL: URL) async {
        await store.remove(fileURL)
    }

    public func cancel() {
        running?.cancel()
        running = nil
    }
}

/// One full-text search result.
public struct TextSearchHit: Sendable, Equatable {
    public var fileURL: URL
    /// Excerpt around the match, for showing why it matched.
    public var snippet: String

    public init(fileURL: URL, snippet: String) {
        self.fileURL = fileURL
        self.snippet = snippet
    }
}
