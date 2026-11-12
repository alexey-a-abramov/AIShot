import CoreGraphics
import Foundation
import OSLog
import AIShotCore
import AIShotCapture
import AIShotPersistence

/// The result of a capture plus the encoded image (for MCP/clipboard reuse).
public struct CaptureOutcome: Sendable {
    public var result: CaptureResult
    public var image: CapturedImage
    /// Where the capture was filed, when it was persisted.
    public var destination: ResolvedDestination?
    /// Set when the configured destination was unwritable and the capture was
    /// saved to the default folder instead. The capture still happened.
    public var saveError: String?

    public init(
        result: CaptureResult,
        image: CapturedImage,
        destination: ResolvedDestination? = nil,
        saveError: String? = nil
    ) {
        self.result = result
        self.image = image
        self.destination = destination
        self.saveError = saveError
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
    /// - Parameters:
    ///   - tag: project tag to file this capture under, when organising by tag.
    ///     Falls back to the "apply last tag" setting — that's the workflow where
    ///     the tag is genuinely known at write time. A capture tagged *later* in
    ///     the prompt keeps its tag in metadata but stays where it was written;
    ///     moving it afterwards would strand history, the OCR index and the
    ///     notes index, which all key off the path.
    ///   - rootOverride: write into this directory instead of the save folder.
    public func deliver(
        _ image: CapturedImage,
        mode: CaptureMode,
        persist: Bool = true,
        tag: String? = nil,
        rootOverride: URL? = nil
    ) async throws -> CaptureOutcome {
        let settings = (try? settingsStore.load()) ?? .default

        var fileURL: URL?
        var destination: ResolvedDestination?
        var saveError: String?
        if persist {
            let name = FileNameFormatter(template: settings.fileNameTemplate)
                .fileName(format: image.format, date: Date())
            let effectiveTag = tag ?? (settings.applyLastTag ? settings.lastTag : nil)
            let resolved = SaveDestinationResolver().resolve(
                settings: settings, tag: effectiveTag, date: Date(), rootOverride: rootOverride
            )
            destination = resolved
            let log = Logger.aishot("capture")
            log.info("delivering \(mode.rawValue, privacy: .public): \(image.data.count, privacy: .public) bytes -> \(resolved.directory.path, privacy: .public)")
            do {
                fileURL = try saver.save(image.data, fileName: name, to: resolved.directory)
            } catch {
                // A misconfigured subfolder must never cost the user the
                // capture: fall back to the default folder and report it.
                saveError = error.localizedDescription
                destination = nil
                log.error("save to \(resolved.directory.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public) - falling back")
                let fallback = AppSettings.default.saveDirectory
                if let recovered = try? saver.save(image.data, fileName: name, to: fallback) {
                    fileURL = recovered
                } else {
                    // Both destinations failed. Record no path: a history row
                    // pointing at a file that was never written shows up as a
                    // phantom "File missing" card in the Dashboard and tells
                    // the user nothing about what went wrong.
                    log.error("fallback save to \(fallback.path, privacy: .public) also failed - no file written")
                    fileURL = nil
                }
            }
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

        // The outputs above hand the file to other subsystems. Confirm it is
        // still on disk before claiming the capture was saved.
        //
        // This caught a real one: UNNotificationAttachment takes ownership of
        // the file it is given and moves it into the notification store, so
        // every captured PNG was deleted moments after being written while
        // history kept a row pointing at it. The result was a Dashboard full
        // of "File missing" cards and nothing, anywhere, saying why.
        if let written = fileURL, !FileManager.default.fileExists(atPath: written.path) {
            Logger.aishot("capture").error("file vanished after delivery: \(written.path, privacy: .public)")
            saveError = CaptureSaveError.vanishedAfterWrite(written).localizedDescription
            fileURL = nil
        }

        // Only record captures that actually produced a file. A row with no
        // path (or a path nothing was written to) becomes an undiagnosable
        // "File missing" card.
        if persist && fileURL == nil {
            Logger.aishot("capture").error("not recording history: nothing was written to disk")
        } else {
            try? await history.record(HistoryEntry(
            fileURL: fileURL,
            createdAt: result.createdAt,
            mode: mode,
            pixelWidth: Int(image.pixelSize.width),
            pixelHeight: Int(image.pixelSize.height)
            ))
        }

        return CaptureOutcome(result: result, image: image, destination: destination, saveError: saveError)
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

    /// Updates an existing history row in place (or records it), for a file
    /// that was overwritten — its pixel size changes after e.g. Beautify.
    public func upsertExisting(_ entry: HistoryEntry) async throws {
        try await history.upsert(entry)
    }

    /// Removes history entries by id. The files themselves are the caller's
    /// responsibility (the app trashes them so they stay recoverable).
    public func removeHistory(ids: Set<UUID>) async throws {
        try await history.remove(ids: ids)
    }
}
