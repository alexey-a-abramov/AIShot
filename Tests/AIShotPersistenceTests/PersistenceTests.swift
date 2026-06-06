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
        modified.copyToClipboard = false
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
}
