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
    func present(_ result: CaptureResult) async { count += 1 }
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

/// Filing captures into subfolders. The point of these is that resolution and
/// the actual write agree — a resolver unit test can't catch a wiring mistake.
struct CaptureServiceDestinationTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-dest-\(UUID().uuidString)", isDirectory: true)
    }

    private func sampleImage() -> CapturedImage {
        CapturedImage(pixelSize: CGSize(width: 10, height: 8), scale: 2, format: .png,
                      data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D]))
    }

    private func service(_ settings: AppSettings) -> CaptureService {
        CaptureService(
            engine: FakeCapturing(image: sampleImage()),
            settingsStore: FakeSettingsStore(settings: settings),
            history: InMemoryHistoryStore()
        )
    }

    private func settings(in root: URL, _ organization: FolderOrganization) -> AppSettings {
        var s = AppSettings.default
        s.saveDirectory = root
        s.folderOrganization = organization
        s.showNotification = false
        s.postCaptureAction = .saveOnly
        return s
    }

    @Test func deliverFilesIntoADateSubfolder() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = try await service(settings(in: root, .byDate))
            .deliver(sampleImage(), mode: .region)

        let url = try #require(outcome.result.fileURL)
        // The parent directory is a date folder inside the root, not the root.
        #expect(url.deletingLastPathComponent() != root)
        #expect(url.path.hasPrefix(root.path))
        #expect(outcome.destination?.subpath.count == 1)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func explicitTagWins() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = try await service(settings(in: root, .byTag))
            .deliver(sampleImage(), mode: .region, tag: "ProjectX")

        #expect(outcome.destination?.subpath == ["ProjectX"])
        #expect(try #require(outcome.result.fileURL).path.contains("/ProjectX/"))
    }

    /// The "run of related screenshots" workflow: the tag is known at write time.
    @Test func lastTagIsUsedWhenApplyLastTagIsOn() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        var s = settings(in: root, .byTag)
        s.applyLastTag = true
        s.lastTag = "Sprint7"

        let outcome = try await service(s).deliver(sampleImage(), mode: .region)
        #expect(outcome.destination?.subpath == ["Sprint7"])
    }

    @Test func anUntaggedCaptureLandsInTheUnsortedFolder() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = try await service(settings(in: root, .byTag))
            .deliver(sampleImage(), mode: .region)
        #expect(outcome.destination?.subpath == ["Unsorted"])
    }

    @Test func rootOverrideRedirectsTheWrite() async throws {
        let root = tempDir(), other = tempDir()
        defer { [root, other].forEach { try? FileManager.default.removeItem(at: $0) } }

        let outcome = try await service(settings(in: root, .none))
            .deliver(sampleImage(), mode: .region, rootOverride: other)
        #expect(try #require(outcome.result.fileURL).path.hasPrefix(other.path))
    }

    /// A misconfigured destination must never cost the user the capture.
    @Test func anUnwritableDestinationFallsBackInsteadOfLosingTheCapture() async throws {
        var s = AppSettings.default
        // /dev/null is a file: creating a directory inside it always fails.
        s.saveDirectory = URL(fileURLWithPath: "/dev/null/nope", isDirectory: true)
        s.showNotification = false
        s.postCaptureAction = .saveOnly

        let outcome = try await service(s).deliver(sampleImage(), mode: .region)
        #expect(outcome.saveError != nil)
        let url = try #require(outcome.result.fileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    /// The app and the MCP helper are separate processes sharing settings; they
    /// must resolve identically or agent captures scatter.
    @Test func twoServicesWithTheSameSettingsResolveIdentically() async throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let s = settings(in: root, .byTagThenDate)

        let a = try await service(s).deliver(sampleImage(), mode: .region, tag: "P")
        let b = try await service(s).deliver(sampleImage(), mode: .region, tag: "P")
        #expect(a.destination?.subpath == b.destination?.subpath)
        #expect(a.result.fileURL?.deletingLastPathComponent()
                == b.result.fileURL?.deletingLastPathComponent())
    }
}
