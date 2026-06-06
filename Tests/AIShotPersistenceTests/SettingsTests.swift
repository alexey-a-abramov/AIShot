import Testing
import Foundation
@testable import AIShotPersistence
@testable import AIShotCore

struct SettingsTests {
    @Test func defaultSettingsAreSane() {
        let settings = AppSettings.default
        #expect(settings.defaultFormat == .png)
        #expect(!settings.fileNameTemplate.isEmpty)
        #expect(settings.copyToClipboard)
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
