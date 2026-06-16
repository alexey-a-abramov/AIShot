import Testing
import Foundation
import CoreGraphics
@testable import AIShotService
@testable import AIShotCore
@testable import AIShotCapture
@testable import AIShotPersistence

private struct FakeCapturing: ScreenCapturing {
    let image: CapturedImage
    func availableDisplays() async throws -> [DisplayInfo] { [] }
    func availableWindows() async throws -> [WindowInfo] { [] }
    func capture(_ request: CaptureRequest) async throws -> CapturedImage { image }
}

private struct FakeSettingsStore: SettingsStore {
    let settings: AppSettings
    func load() throws -> AppSettings { settings }
    func save(_ settings: AppSettings) throws {}
}

private actor SpyClipboard: ClipboardWriting {
    private(set) var copied: [Data] = []
    func copyImage(_ data: Data) async throws { copied.append(data) }
}

private actor SpyNotifier: NotificationPresenting {
    private(set) var count = 0
    private(set) var lastSound: Bool?
    func present(_ result: CaptureResult, sound: Bool) async { count += 1; lastSound = sound }
}

struct CaptureServiceTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-svc-\(UUID().uuidString)", isDirectory: true)
    }

    private func sampleImage() -> CapturedImage {
        CapturedImage(pixelSize: CGSize(width: 10, height: 8), scale: 2, format: .png,
                      data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D]))
    }

    @Test func performCaptureSavesCopiesNotifiesAndRecords() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        var settings = AppSettings.default
        settings.saveDirectory = dir
        settings.postCaptureAction = .copyToClipboard
        settings.showNotification = true

        let clipboard = SpyClipboard()
        let notifier = SpyNotifier()
        let history = InMemoryHistoryStore()
        let service = CaptureService(
            engine: FakeCapturing(image: sampleImage()),
            settingsStore: FakeSettingsStore(settings: settings),
            history: history,
            clipboard: clipboard,
            notifier: notifier
        )

        let outcome = try await service.performCapture(CaptureRequest(mode: .display))

        #expect(outcome.result.fileURL != nil)
        #expect(FileManager.default.fileExists(atPath: outcome.result.fileURL!.path))
        #expect(outcome.result.pixelSize == CGSize(width: 10, height: 8))
        let copied = await clipboard.copied
        #expect(copied.count == 1)
        let notified = await notifier.count
        #expect(notified == 1)
        let recent = try await history.recent(limit: 5)
        #expect(recent.count == 1)
        #expect(recent.first?.pixelWidth == 10)
    }

    @Test func persistFalseSkipsFileButStillCopies() async throws {
        var settings = AppSettings.default
        settings.saveDirectory = tempDir()
        settings.postCaptureAction = .copyToClipboard
        settings.showNotification = false

        let clipboard = SpyClipboard()
        let service = CaptureService(
            engine: FakeCapturing(image: sampleImage()),
            settingsStore: FakeSettingsStore(settings: settings),
            history: InMemoryHistoryStore(),
            clipboard: clipboard,
            notifier: nil
        )

        let outcome = try await service.performCapture(CaptureRequest(mode: .display), persist: false)
        #expect(outcome.result.fileURL == nil)
        let copied = await clipboard.copied
        #expect(copied.count == 1)
    }
}
