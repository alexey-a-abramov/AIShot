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
        let url = dir.appendingPathComponent(CaptureMetadataStore.visibleFileName)

        let store = CaptureMetadataStore()
        try await store.upsert(at: url, key: "a.png", note: "first note", tag: "ProjectX")
        #expect(FileManager.default.fileExists(atPath: url.path))

        // A fresh store reads the persisted metadata.
        let reopened = CaptureMetadataStore()
        let meta = await reopened.metadata(at: url, key: "a.png")
        #expect(meta?.note == "first note")
        #expect(meta?.tag == "ProjectX")
    }

    @Test func tagsAreDistinctTrimmedAndSorted() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(CaptureMetadataStore.visibleFileName)

        let store = CaptureMetadataStore()
        try await store.upsert(at: url, key: "a.png", note: "", tag: "  beta ")
        try await store.upsert(at: url, key: "b.png", note: "", tag: "alpha")
        try await store.upsert(at: url, key: "c.png", note: "", tag: "beta")

        let tags = await store.tags(at: url)
        #expect(tags == ["alpha", "beta"]) // trimmed, de-duplicated, sorted
    }

    @Test func upsertVisibleOnSameInstanceWithoutReopen() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(CaptureMetadataStore.visibleFileName)

        // The apply-last-tag flow re-reads the same store instance immediately,
        // so the cache must reflect the write (not a stale value).
        let store = CaptureMetadataStore()
        try await store.upsert(at: url, key: "a.png", note: "n", tag: "T")
        #expect(await store.metadata(at: url, key: "a.png")?.tag == "T")
        try await store.upsert(at: url, key: "a.png", note: "n2", tag: "U")
        #expect(await store.metadata(at: url, key: "a.png")?.tag == "U")
        #expect(await store.metadata(at: url, key: "a.png")?.note == "n2")
    }

    @Test func hiddenFileGetsHiddenFlag() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(CaptureMetadataStore.hiddenFileName)

        let store = CaptureMetadataStore()
        try await store.upsert(at: url, key: "a.png", note: "n", tag: "T")
        #expect(url.lastPathComponent.hasPrefix("."))
        let isHidden = (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden
        #expect(isHidden == true)
    }

    @Test func moveRelocatesIndex() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let visible = dir.appendingPathComponent(CaptureMetadataStore.visibleFileName)
        let hidden = dir.appendingPathComponent(CaptureMetadataStore.hiddenFileName)

        let store = CaptureMetadataStore()
        try await store.upsert(at: visible, key: "a.png", note: "n", tag: "T")
        await store.move(from: visible, to: hidden)

        #expect(!FileManager.default.fileExists(atPath: visible.path))
        #expect(FileManager.default.fileExists(atPath: hidden.path))
        #expect(await store.metadata(at: hidden, key: "a.png")?.tag == "T")
    }

    @Test func moveMergesIntoExistingTargetWithoutLosingNotes() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let visible = dir.appendingPathComponent(CaptureMetadataStore.visibleFileName)
        let hidden = dir.appendingPathComponent(CaptureMetadataStore.hiddenFileName)

        let store = CaptureMetadataStore()
        try await store.upsert(at: visible, key: "a.png", note: "from visible", tag: "V")
        try await store.upsert(at: hidden, key: "b.png", note: "from hidden", tag: "H")

        // Target (hidden) already exists → merge, don't clobber.
        await store.move(from: visible, to: hidden)
        #expect(!FileManager.default.fileExists(atPath: visible.path))
        #expect(await store.metadata(at: hidden, key: "a.png")?.tag == "V")
        #expect(await store.metadata(at: hidden, key: "b.png")?.tag == "H")
    }

    @Test func nonStandardizedURLResolvesToSameEntry() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = dir.appendingPathComponent(CaptureMetadataStore.visibleFileName)
        // Same file via a non-standardized path (a "." directory segment).
        let messy = dir.appendingPathComponent(".", isDirectory: true)
            .appendingPathComponent(CaptureMetadataStore.visibleFileName)

        let store = CaptureMetadataStore()
        try await store.upsert(at: messy, key: "a.png", note: "x", tag: "T")
        #expect(await store.metadata(at: plain, key: "a.png")?.tag == "T")
        #expect(await store.tags(at: plain) == ["T"])
    }

    @Test func emptyNoteAndTagRemovesEntry() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(CaptureMetadataStore.visibleFileName)

        let store = CaptureMetadataStore()
        try await store.upsert(at: url, key: "a.png", note: "note", tag: "t")
        #expect(await store.metadata(at: url, key: "a.png") != nil)

        try await store.upsert(at: url, key: "a.png", note: "  ", tag: "")
        #expect(await store.metadata(at: url, key: "a.png") == nil)
    }
}
