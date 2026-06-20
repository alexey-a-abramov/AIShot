import Testing
import Foundation
@testable import AIShotPersistence

struct CaptureMetadataStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-meta-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func upsertWritesIndexAndReloads() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = CaptureMetadataStore()
        try await store.upsert(directory: dir, fileName: "a.png", note: "first note", tag: "ProjectX")

        // The sidecar file is written into the capture directory.
        let indexURL = dir.appendingPathComponent(CaptureMetadataStore.fileName)
        #expect(FileManager.default.fileExists(atPath: indexURL.path))

        // A fresh store reads the persisted metadata.
        let reopened = CaptureMetadataStore()
        let meta = await reopened.metadata(directory: dir, fileName: "a.png")
        #expect(meta?.note == "first note")
        #expect(meta?.tag == "ProjectX")
    }

    @Test func tagsAreDistinctTrimmedAndSorted() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = CaptureMetadataStore()
        try await store.upsert(directory: dir, fileName: "a.png", note: "", tag: "  beta ")
        try await store.upsert(directory: dir, fileName: "b.png", note: "", tag: "alpha")
        try await store.upsert(directory: dir, fileName: "c.png", note: "", tag: "beta")

        let tags = await store.tags(for: dir)
        #expect(tags == ["alpha", "beta"]) // trimmed, de-duplicated, sorted
    }

    @Test func upsertVisibleOnSameInstanceWithoutReopen() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // The apply-last-tag flow re-reads the same store instance immediately,
        // so the cache must reflect the write (not a stale value).
        let store = CaptureMetadataStore()
        try await store.upsert(directory: dir, fileName: "a.png", note: "n", tag: "T")
        #expect(await store.metadata(directory: dir, fileName: "a.png")?.tag == "T")
        try await store.upsert(directory: dir, fileName: "a.png", note: "n2", tag: "U")
        #expect(await store.metadata(directory: dir, fileName: "a.png")?.tag == "U")
        #expect(await store.metadata(directory: dir, fileName: "a.png")?.note == "n2")
    }

    @Test func nonStandardizedDirectoryResolvesToSameEntry() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = CaptureMetadataStore()
        // Write through a non-standardized URL (trailing "." segment)…
        let messy = dir.appendingPathComponent(".", isDirectory: true)
        try await store.upsert(directory: messy, fileName: "a.png", note: "x", tag: "T")
        // …and read through the plain URL: must resolve to the same entry.
        #expect(await store.metadata(directory: dir, fileName: "a.png")?.tag == "T")
        #expect(await store.tags(for: dir) == ["T"])
    }

    @Test func emptyNoteAndTagRemovesEntry() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = CaptureMetadataStore()
        try await store.upsert(directory: dir, fileName: "a.png", note: "note", tag: "t")
        #expect(await store.metadata(directory: dir, fileName: "a.png") != nil)

        try await store.upsert(directory: dir, fileName: "a.png", note: "  ", tag: "")
        #expect(await store.metadata(directory: dir, fileName: "a.png") == nil)
    }
}
