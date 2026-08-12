import Testing
import Foundation
@testable import AIShotPersistence
@testable import AIShotCore

struct SettingsTests {
    @Test func defaultSettingsAreSane() {
        let settings = AppSettings.default
        #expect(settings.defaultFormat == .png)
        #expect(!settings.fileNameTemplate.isEmpty)
        #expect(settings.postCaptureAction == .copyToClipboard)
        // Risky MCP actions must be confirmation-gated out of the box.
        #expect(settings.mcpRequireConfirmationForInput)
        #expect(settings.saveDirectory.lastPathComponent == "AIShot")
    }

    @Test func settingsRoundTripThroughJSON() throws {
        let settings = AppSettings.default
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func historyStoreReturnsMostRecentFirst() async throws {
        let store = InMemoryHistoryStore()
        let older = HistoryEntry(fileURL: nil, createdAt: Date(timeIntervalSince1970: 1),
                                 mode: .region, pixelWidth: 10, pixelHeight: 10)
        let newer = HistoryEntry(fileURL: nil, createdAt: Date(timeIntervalSince1970: 2),
                                 mode: .window, pixelWidth: 20, pixelHeight: 20)
        try await store.record(older)
        try await store.record(newer)
        let recent = try await store.recent(limit: 10)
        #expect(recent.count == 2)
        #expect(recent.first == newer)
    }
}

/// Decoding must never be all-or-nothing: `load()` throwing makes `AppModel`
/// fall back to `.default`, which silently resets everything the user set.
struct SettingsResilientDecodingTests {
    @Test func unknownEnumRawValueFallsBackInsteadOfWipingEverything() throws {
        // `postCaptureAction` holds a value this build has never heard of —
        // written by a newer version, or hand-edited.
        let json = """
        {"saveDirectory":"file:///Users/me/Shots/",
         "fileNameTemplate":"MyTemplate {date}",
         "postCaptureAction":"byMoonPhase",
         "captureSoundName":"Tink",
         "mcpEnabled":true}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        // The bad key falls back...
        #expect(settings.postCaptureAction == AppSettings.default.postCaptureAction)
        // ...and every *other* setting survives.
        #expect(settings.fileNameTemplate == "MyTemplate {date}")
        #expect(settings.captureSoundName == "Tink")
        #expect(settings.mcpEnabled == true)
        #expect(settings.saveDirectory.path == "/Users/me/Shots")
    }

    @Test func legacySettingsWithoutNewKeysDecodeWithDefaults() throws {
        // A blob written before several fields existed.
        let json = """
        {"saveDirectory":"file:///Users/me/Pictures/AIShot/",
         "defaultFormat":"png",
         "fileNameTemplate":"AIShot {date} at {time}"}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.fileNameTemplate == "AIShot {date} at {time}")
        #expect(settings.metadataLocation == AppSettings.default.metadataLocation)
        #expect(settings.recordingFormat == AppSettings.default.recordingFormat)
        #expect(settings.captureMetadataEnabled == AppSettings.default.captureMetadataEnabled)
    }
}
