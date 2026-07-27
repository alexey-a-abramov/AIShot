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
        let image = try await engine.capture(request)
        return try await deliver(image, mode: request.mode, persist: persist)
    }

    /// Captures without applying any outputs (for the freeze-frame flow, which
    /// snapshots the screen first and delivers a cropped result later).
    public func rawCapture(_ request: CaptureRequest) async throws -> CapturedImage {
        try await engine.capture(request)
    }

    /// Applies the configured outputs (save / clipboard / notify / history) to an
    /// already-captured image.
    @discardableResult
    public func deliver(_ image: CapturedImage, mode: CaptureMode, persist: Bool = true) async throws -> CaptureOutcome {
        let settings = (try? settingsStore.load()) ?? .default

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
            mode: mode
        )

        if settings.showNotification, let notifier {
            await notifier.present(result)
        }

        try? await history.record(HistoryEntry(
            fileURL: fileURL,
            createdAt: result.createdAt,
            mode: mode,
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

    /// Records an already-saved file (a screen recording, or an edited image
    /// exported from the editor) so it shows up in history alongside captures.
    /// These bypass `deliver` deliberately: their outputs are already written
    /// and re-running the post-capture action would double-notify.
    public func recordExisting(_ entry: HistoryEntry) async throws {
        try await history.record(entry)
    }

    /// Removes history entries by id. The files themselves are the caller's
    /// responsibility (the app trashes them so they stay recoverable).
    public func removeHistory(ids: Set<UUID>) async throws {
        try await history.remove(ids: ids)
    }
}
