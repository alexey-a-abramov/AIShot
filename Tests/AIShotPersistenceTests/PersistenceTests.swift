import Testing
import Foundation
@testable import AIShotPersistence
@testable import AIShotCore

struct FileNameFormatterTests {
    @Test func expandsDateAndTimeTokensDeterministically() {
        let formatter = FileNameFormatter(template: "AIShot {date} at {time}")
        let name = formatter.fileName(
            format: .png,
            date: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(name == "AIShot 1970-01-01 at 00.00.00.png")
    }

    @Test func expandsAppAndSequenceTokens() {
        let formatter = FileNameFormatter(template: "{app}-{seq}")
        let name = formatter.fileName(format: .jpeg, date: Date(), app: "Safari", sequence: 7)
        #expect(name == "Safari-7.jpg")
    }

    @Test func sanitizesPathSeparators() {
        let formatter = FileNameFormatter(template: "a/b:c")
        let name = formatter.fileName(format: .png, date: Date())
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }
}

struct CaptureSaverTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func writesFileAndReturnsURL() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try CaptureSaver().save(Data("hello".utf8), fileName: "shot.png", to: dir)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == Data("hello".utf8))
    }

    @Test func avoidsOverwritingExistingFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saver = CaptureSaver()
        let first = try saver.save(Data("a".utf8), fileName: "shot.png", to: dir)
        let second = try saver.save(Data("b".utf8), fileName: "shot.png", to: dir)
        #expect(first.lastPathComponent == "shot.png")
        #expect(second.lastPathComponent == "shot (2).png")
    }
}

struct UserDefaultsSettingsStoreTests {
    @Test func returnsDefaultWhenEmptyAndRoundTrips() throws {
        let suite = "aishot.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsSettingsStore(defaults: defaults)
        #expect(try store.load() == AppSettings.default)

        var modified = AppSettings.default
        modified.postCaptureAction = .saveOnly
        modified.mcpPort = 50000
        try store.save(modified)
        #expect(try store.load() == modified)
    }
}

struct FileHistoryStoreTests {
    @Test func recordsNewestFirstAndPersists() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileHistoryStore(fileURL: url)
        let older = HistoryEntry(fileURL: nil, createdAt: Date(timeIntervalSince1970: 1),
                                 mode: .region, pixelWidth: 1, pixelHeight: 1)
        let newer = HistoryEntry(fileURL: nil, createdAt: Date(timeIntervalSince1970: 2),
                                 mode: .window, pixelWidth: 2, pixelHeight: 2)
        try await store.record(older)
        try await store.record(newer)

        // A fresh instance must read the persisted file.
        let reopened = FileHistoryStore(fileURL: url)
        let recent = try await reopened.recent(limit: 10)
        #expect(recent.map(\.id) == [newer.id, older.id])
    }

    @Test func removeDeletesFromDiskAndCache() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileHistoryStore(fileURL: url)
        let keep = HistoryEntry(fileURL: nil, createdAt: Date(timeIntervalSince1970: 1),
                                mode: .region, pixelWidth: 1, pixelHeight: 1)
        let drop = HistoryEntry(fileURL: nil, createdAt: Date(timeIntervalSince1970: 2),
                                mode: .window, pixelWidth: 2, pixelHeight: 2)
        try await store.record(keep)
        try await store.record(drop)

        try await store.remove(ids: [drop.id])

        // Same instance reflects the removal (cache stayed coherent)…
        #expect(try await store.recent(limit: 10).map(\.id) == [keep.id])
        // …and so does a fresh one reading the file.
        let reopened = FileHistoryStore(fileURL: url)
        #expect(try await reopened.recent(limit: 10).map(\.id) == [keep.id])
    }

    @Test func removeIsANoOpForUnknownIDs() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileHistoryStore(fileURL: url)
        let entry = HistoryEntry(fileURL: nil, createdAt: Date(), mode: .region,
                                 pixelWidth: 1, pixelHeight: 1)
        try await store.record(entry)
        try await store.remove(ids: [UUID()])
        #expect(try await store.recent(limit: 10).map(\.id) == [entry.id])
    }
}

struct HistoryEntryCodingTests {
    /// History written before `kind` existed must still decode — otherwise an
    /// update silently wipes the user's history.
    @Test func decodesLegacyEntryWithoutKind() throws {
        let legacy = """
        [{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "fileURL":"file:///tmp/a.png",
          "createdAt":760000000,
          "mode":"region",
          "pixelWidth":1254,
          "pixelHeight":512}]
        """
        let decoder = JSONDecoder()
        let entries = try decoder.decode([HistoryEntry].self, from: Data(legacy.utf8))
        #expect(entries.count == 1)
        #expect(entries[0].kind == .image) // defaulted, not thrown
        #expect(entries[0].pixelWidth == 1254)
    }

    @Test func roundTripsKind() throws {
        let entry = HistoryEntry(fileURL: URL(fileURLWithPath: "/tmp/a.mp4"), createdAt: Date(),
                                 mode: .display, pixelWidth: 100, pixelHeight: 50, kind: .video)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)
        #expect(decoded.kind == .video)
        #expect(decoded == entry)
    }
}
