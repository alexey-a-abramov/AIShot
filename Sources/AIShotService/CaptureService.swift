import CoreGraphics
import Foundation
import AIShotCore
import AIShotCapture
import AIShotPersistence

/// The result of a capture plus the encoded image (for MCP/clipboard reuse).
public struct CaptureOutcome: Sendable {
    public var result: CaptureResult
    public var image: CapturedImage
    public init(result: CaptureResult, image: CapturedImage) {
        self.result = result
        self.image = image
    }
}

/// Orchestrates a capture end-to-end: engine → save → clipboard → notify →
/// history, honoring the current `AppSettings`. Shared by the UI, hotkeys, and
/// the MCP server so behavior is identical for humans and agents.
public actor CaptureService {
    private let engine: any ScreenCapturing
    private let settingsStore: any SettingsStore
    private let history: any HistoryStore
    private let clipboard: (any ClipboardWriting)?
    private let notifier: (any NotificationPresenting)?
    private let saver = CaptureSaver()

    public init(
        engine: any ScreenCapturing,
        settingsStore: any SettingsStore,
        history: any HistoryStore,
        clipboard: (any ClipboardWriting)? = nil,
        notifier: (any NotificationPresenting)? = nil
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.history = history
        self.clipboard = clipboard
        self.notifier = notifier
    }

    /// Captures per `request`, applies the configured outputs, records history,
    /// and returns both the result metadata and the encoded image.
    @discardableResult
    public func performCapture(_ request: CaptureRequest, persist: Bool = true) async throws -> CaptureOutcome {
        let settings = (try? settingsStore.load()) ?? .default
        let image = try await engine.capture(request)

        var fileURL: URL?
        if persist {
            let name = FileNameFormatter(template: settings.fileNameTemplate)
                .fileName(format: image.format, date: Date())
            fileURL = try saver.save(image.data, fileName: name, to: settings.saveDirectory)
        }

        if settings.postCaptureAction == .copyToClipboard, let clipboard {
            try? await clipboard.copyImage(image.data)
        }

        let result = CaptureResult(
            fileURL: fileURL,
            pixelSize: image.pixelSize,
            scale: image.scale,
            mode: request.mode
        )

        if settings.showNotification, let notifier {
            await notifier.present(result)
        }

        try? await history.record(HistoryEntry(
            fileURL: fileURL,
            createdAt: result.createdAt,
            mode: request.mode,
            pixelWidth: Int(image.pixelSize.width),
            pixelHeight: Int(image.pixelSize.height)
        ))

        return CaptureOutcome(result: result, image: image)
    }

    // Pass-throughs used by the UI and MCP enumeration tools.
    public func displays() async throws -> [DisplayInfo] { try await engine.availableDisplays() }
    public func windows() async throws -> [WindowInfo] { try await engine.availableWindows() }
    public func recentHistory(limit: Int = 20) async throws -> [HistoryEntry] {
        try await history.recent(limit: limit)
    }
}
