import Testing
import Foundation
@testable import AIShotPersistence

struct CaptureTextIndexStoreTests {
    private func tempIndex() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-text-\(UUID().uuidString)/index.json")
    }

    /// Creates a real file so the store can fingerprint it.
    private func makeFile(_ contents: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-cap-\(UUID().uuidString).png")
        try? Data(contents.utf8).write(to: url)
        return url
    }

    @Test func storesAndReloadsText() async throws {
        let index = tempIndex()
        let file = makeFile("pretend png")
        defer {
            try? FileManager.default.removeItem(at: index.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: file)
        }

        let store = CaptureTextIndexStore(fileURL: index)
        await store.store(text: "Connection refused at line 42", for: file)
        await store.flush()

        // A fresh store reads the persisted index.
        let reopened = CaptureTextIndexStore(fileURL: index)
        #expect(await reopened.text(for: file)?.text == "Connection refused at line 42")
    }

    @Test func needsIndexingIsFalseOnceIndexedAndTrueAfterChange() async throws {
        let index = tempIndex()
        let file = makeFile("v1")
        defer {
            try? FileManager.default.removeItem(at: index.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: file)
        }

        let store = CaptureTextIndexStore(fileURL: index)
        #expect(await store.needsIndexing(file)) // never indexed
        await store.store(text: "hello", for: file)
        #expect(!(await store.needsIndexing(file)))

        // Rewriting the file (different size) invalidates the entry.
        try Data("v2 is longer than v1".utf8).write(to: file)
        #expect(await store.needsIndexing(file))
    }

    @Test func searchMatchesCaseInsensitivelyAndReturnsSnippet() async throws {
        let index = tempIndex()
        let a = makeFile("a"), b = makeFile("b")
        defer {
            try? FileManager.default.removeItem(at: index.deletingLastPathComponent())
            [a, b].forEach { try? FileManager.default.removeItem(at: $0) }
        }

        let store = CaptureTextIndexStore(fileURL: index)
        await store.store(text: "Fatal error: unexpectedly found nil", for: a)
        await store.store(text: "All tests passed", for: b)

        let hits = await store.search("FATAL")
        #expect(hits.count == 1)
        #expect(hits[0].url.standardizedFileURL == a.standardizedFileURL)
        #expect(hits[0].snippet.contains("Fatal error"))

        #expect(await store.search("nothing here").isEmpty)
        #expect(await store.search("   ").isEmpty) // blank query matches nothing
    }

    @Test func pruneMissingDropsDeletedFiles() async throws {
        let index = tempIndex()
        let keep = makeFile("keep"), gone = makeFile("gone")
        defer {
            try? FileManager.default.removeItem(at: index.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: keep)
        }

        let store = CaptureTextIndexStore(fileURL: index)
        await store.store(text: "one", for: keep)
        await store.store(text: "two", for: gone)
        try FileManager.default.removeItem(at: gone)

        #expect(await store.pruneMissing() == 1)
        #expect(await store.text(for: keep) != nil)
        #expect(await store.text(for: gone) == nil)
    }

    @Test func snippetElidesAroundTheMatch() {
        let long = String(repeating: "x", count: 200) + "NEEDLE" + String(repeating: "y", count: 200)
        let snippet = CaptureTextIndexStore.snippet(of: long, around: "NEEDLE", radius: 10)
        #expect(snippet.contains("NEEDLE"))
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.count < 40)
    }
}
