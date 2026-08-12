import AppKit
import Combine
import CoreGraphics
import CryptoKit
import SwiftUI
import AIShotCore
import AIShotCapture
import AIShotAutomation
import AIShotPersistence
import AIShotService
import AIShotShared

/// Central app coordinator. Owns the capture service and shared UI state, and
/// exposes the actions invoked by the menu bar, hotkeys, and windows.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Persists on every change, from any mutator (Settings window, Dashboard,
    // or the menu bar's own Self-Timer/Recording Format pickers) — a view-level
    // `.onChange` would miss mutations made outside that specific view.
    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
    @Published var recent: [HistoryEntry] = []
    @Published var permissions: [Permission: PermissionStatus] = [:]
    @Published var lastError: String?

    /// File the most recent capture was saved to, so "Edit Last Capture" can
    /// overwrite it rather than making a copy.
    @Published private(set) var lastCaptureURL: URL?

    /// The most recent capture, available for "Edit Last Capture".
    @Published private(set) var lastCapture: CapturedImage?

    /// Note/tag metadata for recent captures, keyed by standardized file URL.
    @Published private(set) var captureMeta: [URL: CaptureMetadata] = [:]
    /// All known project tags across the recent captures and save folder.
    @Published private(set) var knownTags: [String] = []
    /// Tagged files confirmed to exist on disk, resolved once per metadata
    /// refresh so tag browsing never hits the filesystem mid-render.
    private var existingTaggedURLs: Set<URL> = []
    private var indexingTask: Task<Void, Never>?
    private var lastSearchQuery = ""

    let captureService: CaptureService
    private let settingsStore: UserDefaultsSettingsStore
    private let permissionsChecker = SystemPermissions()
    private let overlay = SelectionOverlayController()
    private let countdown = CaptureCountdownController()
    private let recognizer = TextRecognizer()
    private let recorder = ScreenRecorder()
    private let scroller = ScrollingCapture()
    private let pinController = PinnedWindowController()
    private let hud = CaptureHUDController()
    private let editorWindow = EditorWindowController()
    private let updater = UpdaterController()
    let metadataStore = CaptureMetadataStore()
    private let tagPrompt = CaptureTagPromptController()
    /// Full-text (OCR) index over captures, powering search here and the
    /// `search_captures` MCP tool.
    let textIndexer = TextIndexer(store: CaptureTextIndexStore(fileURL: AppPaths.textIndexFile))

    private lazy var settingsWindow = HostingWindowController(
        title: "Settings",
        size: NSSize(width: 860, height: 580),
        minSize: NSSize(width: 720, height: 520),
        autosaveName: "AIShotSettingsWindow"
    ) { [unowned self] in AnyView(SettingsView().environmentObject(self)) }

    private lazy var dashboardWindow = HostingWindowController(
        title: String(localized: "Dashboard"),
        size: NSSize(width: 980, height: 660),
        // Matches the split view's column minimums (200 + 400 + 250 + chrome);
        // anything smaller can't satisfy them and clips the inspector.
        minSize: NSSize(width: 880, height: 520),
        autosaveName: "AIShotDashboardWindow"
    ) { [unowned self] in AnyView(DashboardView().environmentObject(self)) }

    @Published var isRecording = false

    private init() {
        let store = UserDefaultsSettingsStore()
        self.settingsStore = store
        self.settings = (try? store.load()) ?? .default
        self.captureService = CaptureService(
            engine: ScreenCaptureKitEngine(),
            settingsStore: store,
            history: FileHistoryStore(fileURL: AppPaths.historyFile),
            clipboard: AppKitClipboard(),
            notifier: UserNotificationPresenter()
        )
        // Re-check permissions whenever the app becomes active (e.g. after the
        // user grants a permission in System Settings and switches back).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshPermissions() }
        }
        // Carry forward any pre-existing visible index now that hidden is default.
        Task { @MainActor [weak self] in await self?.migrateLegacyMetadataIfNeeded() }
    }

    // MARK: - Capture actions

    func captureRegion() {
        Task { await captureRegionInteractive() }
    }

    /// Presents the region overlay (respecting the freeze-frame and self-timer
    /// settings), delivers the result through the standard pipeline, and
    /// returns the outcome — or `nil` if the user cancelled or an error
    /// occurred. Shared by the menu/hotkey action and the Shortcuts/Siri
    /// "Capture Region" intent.
    @discardableResult
    func captureRegionInteractive() async -> CaptureOutcome? {
        if settings.freezeBeforeRegionSelect {
            return await frozenRegionCapture()
        } else {
            return await liveRegionCapture()
        }
    }

    private func liveRegionCapture() async -> CaptureOutcome? {
        guard let selection = await selectRegion(frozen: nil)?.selection else { return nil }
        return await run(CaptureRequest(
            mode: .region, displayID: selection.displayID, rect: selection.rect,
            includeCursor: settings.includeCursor, format: settings.defaultFormat
        ))
    }

    /// Freeze-frame region capture: snapshot every display into memory, let the
    /// user select against the frozen image, then crop & deliver (or discard on
    /// cancel — nothing is captured if the user cancels).
    private func frozenRegionCapture() async -> CaptureOutcome? {
        dismissEphemeralCaptureUI()
        do {
            let displays = try await captureService.displays()
            var images: [CGDirectDisplayID: NSImage] = [:]
            var captures: [CGDirectDisplayID: CapturedImage] = [:]
            for display in displays {
                let snapshot = try await captureService.rawCapture(CaptureRequest(
                    mode: .display, displayID: display.id,
                    includeCursor: settings.includeCursor, format: .png
                ))
                captures[display.id] = snapshot
                if let nsImage = NSImage(data: snapshot.data) { images[display.id] = nsImage }
            }
            guard let picked = await selectRegion(frozen: images) else { return nil }
            let selection = picked.selection

            // With a self-timer, re-capture fresh after the countdown so the
            // delay actually has an effect — the pre-countdown snapshot above
            // is only used to help pick the region, not as the final pixels.
            let source: CapturedImage
            if settings.captureDelay > 0 {
                await countdown.run(seconds: Int(settings.captureDelay))
                source = try await captureService.rawCapture(CaptureRequest(
                    mode: .display, displayID: selection.displayID,
                    includeCursor: settings.includeCursor, format: .png
                ))
            } else {
                // Only reachable if a display disconnected between the initial
                // snapshot and the user completing the selection.
                guard let frozen = captures[selection.displayID] else {
                    lastError = "Selected display is no longer available."
                    return nil
                }
                source = frozen
            }
            return await deliverFrozenRegion(source, selection: selection)
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    /// Bridges the overlay's completion-closure API to async/await.
    private func selectRegion(frozen: [CGDirectDisplayID: NSImage]?) async -> CaptureSelectionResult? {
        await withCheckedContinuation { continuation in
            overlay.begin(frozen: frozen) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func deliverFrozenRegion(_ frozen: CapturedImage, selection: RegionSelection) async -> CaptureOutcome? {
        guard let cropped = Self.crop(frozen, toPointRect: selection.rect, format: settings.defaultFormat) else {
            lastError = "Could not crop the selected region."
            return nil
        }
        do {
            let outcome = try await captureService.deliver(cropped, mode: .region)
            await handleOutcome(outcome)
            return outcome
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    /// Crops a full-display snapshot to a display-local, top-left point rect.
    private static func crop(_ image: CapturedImage, toPointRect rect: CGRect, format: ImageFormat) -> CapturedImage? {
        guard let cgImage = try? ImageCodec.decode(image.data) else { return nil }
        let scale = image.scale
        let pixelRect = CGRect(
            x: (rect.minX * scale).rounded(),
            y: (rect.minY * scale).rounded(),
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
        let clamped = pixelRect.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard !clamped.isEmpty, let cropped = cgImage.cropping(to: clamped),
              let data = try? ImageCodec.encode(cropped, as: format) else { return nil }
        return CapturedImage(
            pixelSize: CGSize(width: cropped.width, height: cropped.height),
            scale: scale, format: format, data: data
        )
    }

    func captureFullScreen() {
        Task { await captureFullScreenReturningPath() }
    }

    func captureFrontWindow() {
        Task { await captureFrontWindowReturningPath() }
    }

    /// Captures every connected display, stitched into one image.
    func captureAllDisplays() {
        Task { await captureAllDisplaysReturningPath() }
    }

    /// Region-select, capture, OCR, and copy the recognized text to the clipboard.
    /// Deliberately bypasses the self-timer and freeze-frame settings — both are
    /// about giving a screenshot's *content* time to settle, which doesn't apply
    /// to a quick, immediate text grab.
    func captureTextOCR() {
        dismissEphemeralCaptureUI()
        overlay.begin { [weak self] result in
            guard let self, let selection = result?.selection else { return }
            Task { @MainActor in
                do {
                    let outcome = try await self.captureService.performCapture(
                        CaptureRequest(mode: .region, displayID: selection.displayID, rect: selection.rect, format: .png),
                        persist: false
                    )
                    let text = try await self.recognizer.recognizeText(in: outcome.image.data)
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    self.lastError = text.isEmpty ? "No text found." : "Copied \(text.count) characters."
                    self.playCaptureSound()
                    self.hud.show(
                        message: text.isEmpty ? String(localized: "No text found") : String(localized: "Text copied"),
                        thumbnail: nil
                    )
                } catch {
                    self.lastError = String(describing: error)
                }
            }
        }
    }

    /// Region-select, then scroll-and-stitch into one tall screenshot.
    /// Deliberately bypasses the self-timer and freeze-frame settings — see
    /// `captureTextOCR`.
    func scrollingCapture() {
        dismissEphemeralCaptureUI()
        overlay.begin { [weak self] result in
            guard let self, let selection = result?.selection else { return }
            Task { @MainActor in
                do {
                    let data = try await self.scroller.capture(displayID: selection.displayID, rect: selection.rect, frames: 8)
                    await self.export(data, copy: true, save: true)
                    self.lastError = "Scrolling capture saved."
                    self.playCaptureSound()
                    self.hud.show(message: String(localized: "Saved"), thumbnail: NSImage(data: data))
                } catch {
                    self.lastError = String(describing: error)
                }
            }
        }
    }

    /// System eyedropper: copies the picked pixel color as a hex string.
    func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let color else { return }
            let srgb = color.usingColorSpace(.sRGB) ?? color
            let hex = String(
                format: "#%02X%02X%02X",
                Int((srgb.redComponent * 255).rounded()),
                Int((srgb.greenComponent * 255).rounded()),
                Int((srgb.blueComponent * 255).rounded())
            )
            Task { @MainActor in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
                self?.lastError = "Copied \(hex)"
            }
        }
    }

    /// Pins the most recent capture in a floating window.
    func pinLastCapture() {
        guard let capture = lastCapture, let image = NSImage(data: capture.data) else { return }
        pinController.pin(image)
    }

    /// Starts or stops screen recording of the main display.
    func toggleRecording() {
        Task {
            do {
                if await recorder.isRecording {
                    let url = try await recorder.stop()
                    isRecording = false
                    let (final, gifFailed) = await finishRecording(url)
                    await recordFinishedRecording(final)
                    lastError = gifFailed
                        ? "Saved recording (GIF export failed): \(final.lastPathComponent)"
                        : "Saved recording: \(final.lastPathComponent)"
                } else {
                    let formatter = DateFormatter()
                    // POSIX locale, like FileNameFormatter: otherwise a non-Gregorian
                    // regional calendar (e.g. Thai Buddhist) writes year 2569 into the
                    // file name.
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
                    let name = "AIShot Recording \(formatter.string(from: Date())).mp4"
                    try FileManager.default.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
                    let url = settings.saveDirectory.appendingPathComponent(name)
                    try await recorder.start(displayID: CGMainDisplayID(), to: url)
                    isRecording = true
                    lastError = "Recording…"
                }
            } catch { lastError = String(describing: error) }
        }
    }

    /// Records a finished recording into history so it appears in the Dashboard
    /// alongside screenshots. Recordings are written straight to disk by
    /// `ScreenRecorder`, bypassing `CaptureService.deliver` (which would
    /// re-apply the post-capture action and re-notify), so history has to be
    /// updated explicitly here.
    private func recordFinishedRecording(_ url: URL) async {
        let kind = Self.kind(for: url)
        let size: CGSize
        switch kind {
        case .video:
            size = await VideoThumbnail.pixelSize(contentsOf: url) ?? .zero
        case .image:
            // A GIF recording is still an image file — ImageIO reads it.
            size = await Task.detached {
                (try? ImageCodec.decode(Data(contentsOf: url)))
                    .map { CGSize(width: $0.width, height: $0.height) } ?? .zero
            }.value
        }
        try? await captureService.recordExisting(HistoryEntry(
            fileURL: url,
            createdAt: Date(),
            mode: .display,
            pixelWidth: Int(size.width),
            pixelHeight: Int(size.height),
            kind: kind
        ))
        await refreshRecent()
    }

    /// Classifies a file for thumbnailing and for which actions apply.
    ///
    /// GIF counts as an **image**: ImageIO decodes frame 0 fine, whereas
    /// AVFoundation can't open one at all — and treating it as an image also
    /// keeps Open in Editor / Copy / Pin available for GIF recordings.
    static func kind(for url: URL) -> CaptureKind {
        ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) ? .video : .image
    }

    /// When the recording format is GIF, transcodes the just-recorded video and
    /// removes the intermediate `.mp4`; otherwise returns it unchanged. GIF
    /// export failures keep the original video so nothing is lost.
    private func finishRecording(_ videoURL: URL) async -> (url: URL, gifFailed: Bool) {
        guard settings.recordingFormat == .gif else { return (videoURL, false) }
        do {
            let gifURL = try await GIFExporter().export(videoURL: videoURL)
            try? FileManager.default.removeItem(at: videoURL)
            return (gifURL, false)
        } catch {
            return (videoURL, true)
        }
    }

    /// Captures the main display, returning the saved file path — used by the
    /// menu/hotkey action and the "Capture Full Screen" Shortcuts/Siri intent.
    @discardableResult
    func captureFullScreenReturningPath() async -> String? {
        await run(CaptureRequest(
            mode: .display, displayID: CGMainDisplayID(),
            includeCursor: settings.includeCursor, format: settings.defaultFormat
        ))?.result.fileURL?.path
    }

    /// Captures the frontmost window, returning the saved file path — used by
    /// the menu/hotkey action and the "Capture Window" Shortcuts/Siri intent.
    @discardableResult
    func captureFrontWindowReturningPath() async -> String? {
        let windows = (try? await captureService.windows()) ?? []
        guard let target = windows.first(where: { $0.isOnScreen && !$0.title.isEmpty }) else {
            lastError = "No window available to capture."
            return nil
        }
        return await run(CaptureRequest(
            mode: .window, windowID: target.id,
            includeCursor: settings.includeCursor, format: settings.defaultFormat
        ))?.result.fileURL?.path
    }

    /// Captures every connected display, stitched into one image, returning
    /// the saved file path.
    @discardableResult
    func captureAllDisplaysReturningPath() async -> String? {
        await run(CaptureRequest(
            mode: .allDisplays, includeCursor: settings.includeCursor, format: settings.defaultFormat
        ))?.result.fileURL?.path
    }

    /// Runs the self-timer countdown (if configured), executes `request`, and
    /// delivers the outcome through the standard pipeline (save/clipboard/
    /// notify/history, feedback, editor, notes prompt).
    @discardableResult
    private func run(_ request: CaptureRequest) async -> CaptureOutcome? {
        dismissEphemeralCaptureUI()
        if settings.captureDelay > 0 {
            await countdown.run(seconds: Int(settings.captureDelay))
        }
        do {
            let outcome = try await captureService.performCapture(request)
            await handleOutcome(outcome)
            return outcome
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    /// Shared post-capture handling: remember, refresh, feedback, open editor,
    /// then attach a note/tag (silently or via the prompt).
    private func handleOutcome(_ outcome: CaptureOutcome) async {
        lastCapture = outcome.image
        lastCaptureURL = outcome.result.fileURL
        // The capture still succeeded — it just didn't land where configured.
        if let saveError = outcome.saveError {
            lastError = String(
                format: String(localized: "Couldn’t use the configured folder (%@). Saved to the default folder instead."),
                saveError
            )
        }
        await refreshRecent()
        feedback(for: outcome)
        if settings.postCaptureAction == .openEditor {
            openEditor(imageData: outcome.image.data, pixelSize: outcome.image.pixelSize,
                       sourceURL: outcome.result.fileURL)
        }
        await promptOrApplyMetadata(for: outcome)
        // Keep the search index current, so a capture taken while the Dashboard
        // is open is searchable without reopening it.
        indexCapturesForSearch()
    }

    // MARK: - Notes & tags

    /// After a saved capture, either silently apply the last tag (when
    /// "apply last tag" is on) or present the note/tag prompt.
    private func promptOrApplyMetadata(for outcome: CaptureOutcome) async {
        guard settings.captureMetadataEnabled, let fileURL = outcome.result.fileURL else { return }
        let loc = metadataLocator(for: fileURL)

        // Silently reuse the last tag (no interruption), even when the editor opens.
        if settings.applyLastTag, let tag = settings.lastTag, !tag.isEmpty {
            try? await metadataStore.upsert(at: loc.indexURL, key: loc.key, note: "", tag: tag)
            await refreshMetadata(for: recent)
            return
        }

        // The editor is the richer surface; don't stack a prompt on top of it.
        guard settings.postCaptureAction != .openEditor else { return }

        let known = await metadataStore.tags(at: loc.indexURL)
        let thumbnail = NSImage(data: outcome.image.data)
        tagPrompt.present(
            fileName: fileURL.lastPathComponent,
            thumbnail: thumbnail,
            suggestedTag: settings.lastTag,
            knownTags: known,
            applyToNext: settings.applyLastTag
        ) { [weak self] result in
            guard let self, let result else { return }
            Task { @MainActor in
                await self.applyPromptResult(result, fileURL: fileURL)
            }
        }
    }

    private func applyPromptResult(_ result: CaptureTagPromptController.Result, fileURL: URL) async {
        let loc = metadataLocator(for: fileURL)
        let tag = result.tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        try? await metadataStore.upsert(at: loc.indexURL, key: loc.key, note: result.note, tag: tag)
        if let tag, !tag.isEmpty { settings.lastTag = tag }
        // "Apply to next" only makes sense if there's actually a tag to reuse.
        settings.applyLastTag = result.applyToNext && (settings.lastTag?.isEmpty == false)
        await refreshMetadata(for: recent)
    }

    /// Metadata for a history entry, if any.
    func metadata(for entry: HistoryEntry) -> CaptureMetadata? {
        guard let url = entry.fileURL?.standardizedFileURL else { return nil }
        return captureMeta[url]
    }

    /// Updates note/tag for a capture from the dashboard editor.
    func updateMetadata(for entry: HistoryEntry, note: String, tag: String?) async {
        guard let fileURL = entry.fileURL else { return }
        let loc = metadataLocator(for: fileURL)
        let cleanTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        try? await metadataStore.upsert(at: loc.indexURL, key: loc.key, note: note, tag: cleanTag)
        if let cleanTag, !cleanTag.isEmpty { settings.lastTag = cleanTag }
        await refreshMetadata(for: recent)
    }

    /// Applies a tag to many captures at once, grouped by index file so each is
    /// written once rather than once per capture.
    func applyTag(_ tag: String, to entries: [HistoryEntry]) async {
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !entries.isEmpty else { return }

        var byIndex: [URL: [String]] = [:]
        for entry in entries {
            guard let fileURL = entry.fileURL else { continue }
            let loc = metadataLocator(for: fileURL)
            byIndex[loc.indexURL, default: []].append(loc.key)
        }
        for (indexURL, keys) in byIndex {
            try? await metadataStore.upsertMany(at: indexURL, keys: keys, note: nil, tag: clean)
        }
        settings.lastTag = clean
        await refreshMetadata(for: recent)
    }

    // MARK: - Actions on an existing capture

    /// Opens a past capture in the annotation editor. Videos aren't editable.
    func openInEditor(_ entry: HistoryEntry) {
        guard entry.kind == .image, let url = entry.fileURL else { return }
        Task {
            guard let data = await Self.readFile(url) else {
                lastError = "Could not read \(url.lastPathComponent)."
                return
            }
            // Entries synthesized from the tag index have no recorded pixel
            // size; the editor lays out everything from it, so a zero size
            // would open a blank canvas. Derive it from the bytes instead.
            var size = CGSize(width: entry.pixelWidth, height: entry.pixelHeight)
            if size.width <= 0 || size.height <= 0 {
                size = await Task.detached {
                    (try? ImageCodec.decode(data))
                        .map { CGSize(width: $0.width, height: $0.height) } ?? .zero
                }.value
            }
            guard size.width > 0, size.height > 0 else {
                lastError = "Could not read \(url.lastPathComponent)."
                return
            }
            openEditor(imageData: data, pixelSize: size, sourceURL: url)
        }
    }

    /// Copies a past capture's image to the clipboard.
    func copyToClipboard(_ entry: HistoryEntry) {
        guard entry.kind == .image, let url = entry.fileURL else { return }
        Task {
            guard let data = await Self.readFile(url) else {
                lastError = "Could not read \(url.lastPathComponent)."
                return
            }
            try? await AppKitClipboard().copyImage(data)
            hud.show(message: String(localized: "Copied to clipboard"), thumbnail: NSImage(data: data))
        }
    }

    /// Pins a past capture in a floating always-on-top window.
    func pin(_ entry: HistoryEntry) {
        guard entry.kind == .image, let url = entry.fileURL else { return }
        Task {
            guard let data = await Self.readFile(url), let image = NSImage(data: data) else {
                lastError = "Could not read \(url.lastPathComponent)."
                return
            }
            pinController.pin(image)
        }
    }

    /// Copies several captures to the clipboard at once.
    ///
    /// Writes the **file URLs**, not decoded bitmaps: Mail, Finder, Slack and
    /// Messages all accept that as N attachments, whereas multiple `NSImage`s
    /// collapse to a single image in most readers — and decoding a large
    /// selection would pull gigabytes into memory.
    func copyToClipboard(_ entries: [HistoryEntry]) {
        let urls = entries.filter { $0.kind == .image }.compactMap(\.fileURL)
        guard !urls.isEmpty else { return }
        guard urls.count > 1 else {
            if let entry = entries.first(where: { $0.kind == .image }) { copyToClipboard(entry) }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
        hud.show(
            message: String(format: String(localized: "Copied %lld images"), urls.count),
            thumbnail: nil
        )
    }

    func revealInFinder(_ entry: HistoryEntry) {
        guard let url = entry.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Moves captures to the Trash and drops their history + metadata entries.
    ///
    /// Uses `NSWorkspace.recycle` rather than deleting outright, so the files
    /// stay recoverable with Finder's own "Put Back" — deleting a screenshot is
    /// not worth making irreversible.
    func delete(_ entries: [HistoryEntry]) async {
        guard !entries.isEmpty else { return }
        let urls = entries.compactMap(\.fileURL)

        var trashed: Set<URL> = []
        if !urls.isEmpty {
            trashed = await withCheckedContinuation { continuation in
                NSWorkspace.shared.recycle(urls) { newURLs, error in
                    if let error { Task { @MainActor in self.lastError = error.localizedDescription } }
                    continuation.resume(returning: Set(newURLs.keys.map(\.standardizedFileURL)))
                }
            }
        }

        // Only forget a capture whose file actually went away — otherwise a
        // failed trash (locked volume, no permission) would destroy the history
        // row and its note/tag while leaving the file on disk. A row whose file
        // was already gone is still removable, so stale entries can be cleared.
        let removed = entries.filter { entry in
            guard let url = entry.fileURL?.standardizedFileURL else { return true }
            return trashed.contains(url) || !FileManager.default.fileExists(atPath: url.path)
        }
        guard !removed.isEmpty else { return }

        // Match by file too: an entry synthesized from the tag index carries a
        // derived id, so removing by id alone would leave the real row behind.
        let removedURLs = Set(removed.compactMap { $0.fileURL?.standardizedFileURL })
        var ids = Set(removed.map(\.id))
        let allRows = (try? await captureService.recentHistory(limit: 10_000)) ?? []
        ids.formUnion(allRows.filter { row in
            guard let url = row.fileURL?.standardizedFileURL else { return false }
            return removedURLs.contains(url)
        }.map(\.id))
        try? await captureService.removeHistory(ids: ids)

        // Clear each capture's note/tag (an empty upsert removes the entry).
        for entry in removed {
            guard let fileURL = entry.fileURL else { continue }
            let loc = metadataLocator(for: fileURL)
            try? await metadataStore.upsert(at: loc.indexURL, key: loc.key, note: "", tag: nil)
            await ThumbnailLoader.shared.invalidate(fileURL)
            await textIndexer.forget(fileURL)
        }

        await refreshRecent()
    }

    // MARK: - Full-text search

    /// Full-text hits for a specific query. Carrying the query alongside the
    /// results lets the UI ignore matches that belong to an older keystroke,
    /// which would otherwise briefly widen the visible set.
    struct TextMatches: Equatable {
        var query = ""
        var hits: [URL: String] = [:]
    }

    /// Captures whose OCR'd text matches the current query, keyed by file URL
    /// with the matching excerpt. Empty until the background index has run.
    @Published private(set) var textMatches = TextMatches()

    /// Kicks off (or continues) background OCR indexing of the current history.
    /// Safe to call repeatedly: already-indexed, unchanged files are skipped.
    func indexCapturesForSearch() {
        guard indexingTask == nil else { return }
        let entries = recent
        indexingTask = Task { [weak self] in
            guard let self else { return }
            await textIndexer.pruneMissing()
            _ = await textIndexer.index(entries)
            self.indexingTask = nil
            // Re-run the active query now that more text is available.
            await self.updateTextMatches(for: self.lastSearchQuery)
        }
    }

    /// Recomputes full-text matches for `query` (too-short clears them).
    func updateTextMatches(for query: String) async {
        lastSearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            textMatches = TextMatches(query: trimmed, hits: [:])
            return
        }
        let hits = await textIndexer.search(trimmed)
        // Ignore a result that arrived after the user typed something else.
        guard trimmed == lastSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        textMatches = TextMatches(
            query: trimmed,
            hits: Dictionary(
                hits.map { ($0.fileURL.standardizedFileURL, $0.snippet) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    /// The OCR excerpt explaining why a capture matched `query` — `nil` unless
    /// the stored matches were computed for that exact query.
    func textSnippet(for entry: HistoryEntry, query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, textMatches.query == trimmed,
              let url = entry.fileURL?.standardizedFileURL else { return nil }
        return textMatches.hits[url]
    }

    /// History rows whose file is gone — shown as "File missing" cards, and
    /// clearable in one go via `removeMissingEntries()`.
    var missingEntries: [HistoryEntry] {
        recent.filter { entry in
            guard let url = entry.fileURL else { return true }
            return !FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Drops history rows whose files no longer exist. Nothing is deleted from
    /// disk — the files are already gone (moved or trashed outside the app);
    /// this just clears the stale rows they left behind.
    func removeMissingEntries() async {
        let stale = missingEntries
        guard !stale.isEmpty else { return }
        try? await captureService.removeHistory(ids: Set(stale.map(\.id)))
        await refreshRecent()
    }

    /// Reads a file off the main actor.
    private static func readFile(_ url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
    }

    // MARK: Metadata location

    /// Resolves the index file + entry key for a capture, honoring the chosen
    /// `metadataLocation` (hidden/visible beside the image, or a shared database).
    private func metadataLocator(for fileURL: URL) -> (indexURL: URL, key: String) {
        switch settings.metadataLocation {
        case .hidden:
            return (fileURL.deletingLastPathComponent()
                        .appendingPathComponent(CaptureMetadataStore.hiddenFileName),
                    fileURL.lastPathComponent)
        case .visible:
            return (fileURL.deletingLastPathComponent()
                        .appendingPathComponent(CaptureMetadataStore.visibleFileName),
                    fileURL.lastPathComponent)
        case .custom:
            let dir = settings.metadataCustomDirectory ?? AppPaths.supportDirectory
            return (dir.appendingPathComponent(CaptureMetadataStore.hiddenFileName),
                    fileURL.standardizedFileURL.path)
        }
    }

    /// The index file backing the current save folder, used to populate the
    /// dashboard's tag list even before its captures appear in recent history.
    private func primaryMetadataIndexURL() -> URL {
        switch settings.metadataLocation {
        case .hidden:
            return settings.saveDirectory.appendingPathComponent(CaptureMetadataStore.hiddenFileName)
        case .visible:
            return settings.saveDirectory.appendingPathComponent(CaptureMetadataStore.visibleFileName)
        case .custom:
            let dir = settings.metadataCustomDirectory ?? AppPaths.supportDirectory
            return dir.appendingPathComponent(CaptureMetadataStore.hiddenFileName)
        }
    }

    /// Resolved folder of the active metadata database (for display in settings).
    var metadataDatabaseDirectory: URL {
        switch settings.metadataLocation {
        case .hidden, .visible: return settings.saveDirectory
        case .custom: return settings.metadataCustomDirectory ?? AppPaths.supportDirectory
        }
    }

    /// File name of the active metadata database (for display in settings).
    var metadataDatabaseFileName: String {
        settings.metadataLocation == .visible
            ? CaptureMetadataStore.visibleFileName
            : CaptureMetadataStore.hiddenFileName
    }

    /// Changes the database location, migrating the file when it's a safe rename
    /// (the two per-directory modes share the same keys; custom uses different
    /// keys, so we don't move across that boundary).
    func setMetadataLocation(_ newLocation: MetadataLocation) async {
        let oldLocation = settings.metadataLocation
        guard oldLocation != newLocation else { return }
        let oldURL = primaryMetadataIndexURL()
        settings.metadataLocation = newLocation
        let newURL = primaryMetadataIndexURL()
        let perDirectory: (MetadataLocation) -> Bool = { $0 == .hidden || $0 == .visible }
        if perDirectory(oldLocation), perDirectory(newLocation), oldURL != newURL {
            await metadataStore.move(from: oldURL, to: newURL)
        }
        await refreshMetadata(for: recent)
    }

    /// Points the shared database at a new folder, moving the existing file.
    func setMetadataCustomDirectory(_ url: URL) async {
        let oldURL = primaryMetadataIndexURL()
        settings.metadataCustomDirectory = url
        let newURL = primaryMetadataIndexURL()
        if settings.metadataLocation == .custom, oldURL != newURL {
            await metadataStore.move(from: oldURL, to: newURL)
        }
        await refreshMetadata(for: recent)
    }

    /// One-time: if the default switched to hidden but a legacy visible index
    /// exists in the save folder, rename it so existing notes carry over.
    private func migrateLegacyMetadataIfNeeded() async {
        guard settings.metadataLocation == .hidden else { return }
        let visible = settings.saveDirectory.appendingPathComponent(CaptureMetadataStore.visibleFileName)
        let hidden = settings.saveDirectory.appendingPathComponent(CaptureMetadataStore.hiddenFileName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: visible.path), !fm.fileExists(atPath: hidden.path) else { return }
        await metadataStore.move(from: visible, to: hidden)
        await refreshMetadata(for: recent)
    }

    /// Dismisses any lingering ephemeral capture-time UI — the post-capture
    /// HUD (normally fades over ~1.8s) and the note/tag prompt (stays open
    /// until Save/Skip) — immediately, before a new capture's actual pixel
    /// grab. AIShot's own windows are no longer excluded from captures (so
    /// the app itself can be screenshotted), so without this a rapid second
    /// capture could otherwise show a leftover HUD or prompt from the first.
    private func dismissEphemeralCaptureUI() {
        hud.dismiss()
        tagPrompt.dismiss()
        // A leftover overlay from an abandoned capture would dim the screen the
        // next one is about to grab.
        overlay.cancel()
    }

    /// Plays the capture sound and shows the fade-in HUD for a finished capture.
    private func feedback(for outcome: CaptureOutcome) {
        playCaptureSound()
        let message: String
        switch settings.postCaptureAction {
        case .copyToClipboard: message = String(localized: "Copied to clipboard")
        case .openEditor: message = String(localized: "Opening editor…")
        case .saveOnly: message = String(localized: "Saved")
        }
        hud.show(message: message, thumbnail: NSImage(data: outcome.image.data))
    }

    /// Plays the configured system sound (unless set to "None").
    private func playCaptureSound() {
        let name = settings.captureSoundName
        guard !name.isEmpty, name != "None", let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.play()
    }

    // MARK: - Editor

    /// Opens the annotation editor on the given image.
    /// - Parameter sourceURL: the file this image is on disk as, when it has
    ///   one. ⌘S in the editor writes back to it instead of making a copy.
    func openEditor(imageData: Data, pixelSize: CGSize, sourceURL: URL? = nil) {
        editorWindow.present(imageData: imageData, pixelSize: pixelSize,
                             sourceURL: sourceURL, app: self)
    }

    /// Opens the editor on the most recent capture.
    func editLastCapture() {
        guard let capture = lastCapture else { return }
        openEditor(imageData: capture.data, pixelSize: capture.pixelSize,
                   sourceURL: lastCaptureURL)
    }

    func openSettings() { settingsWindow.show() }
    func openDashboard() { dashboardWindow.show() }

    /// Opens the bundled offline help page in the default browser. Falls back
    /// to the project's README online if the resource is somehow missing.
    func openHelp() {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Help")
            ?? Bundle.main.url(forResource: "index", withExtension: "html") {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "https://github.com/alexey-a-abramov/AIShot") {
            NSWorkspace.shared.open(fallback)
        }
    }

    /// Saves and/or copies edited image bytes using the current settings.
    ///
    /// A saved export is recorded in history too — it bypasses
    /// `CaptureService.deliver` (which would re-apply the post-capture action
    /// and re-notify), so without this an annotated image would silently never
    /// appear in the Dashboard.
    /// Saves and/or copies edited image bytes.
    ///
    /// `saveAs` always asks for a location. Otherwise the destination follows
    /// `resolveSaveIntent`: overwrite the file the editor opened, else write a
    /// new one into the configured folder.
    func export(
        _ data: Data,
        copy: Bool,
        save: Bool,
        saveAs: Bool = false,
        editor: EditorModel? = nil
    ) async {
        if copy {
            try? await AppKitClipboard().copyImage(data)
        }
        guard save || saveAs else { return }

        let sourceURL = editor?.sourceURL
        let exists = sourceURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let intent = resolveSaveIntent(
            sourceURL: sourceURL,
            sourceExists: exists,
            overwriteEnabled: settings.editorSaveOverwritesOriginal,
            settings: settings,
            tag: settings.applyLastTag ? settings.lastTag : nil,
            date: Date()
        )

        var target: URL
        var format: ImageFormat
        if saveAs {
            let suggested: String
            let directory: URL
            switch intent {
            case .overwrite(let url, let fmt):
                suggested = url.lastPathComponent
                format = fmt
                directory = url.deletingLastPathComponent()
            case .newFile(let dir, let name):
                suggested = name
                format = settings.defaultFormat
                directory = dir
            }
            let seed = (settings.rememberLastSaveAsDirectory ? settings.lastSaveAsDirectory : nil)
                ?? directory
            guard let chosen = await SaveAsPanel.run(.init(
                suggestedName: suggested, directory: seed,
                format: format, host: NSApp.keyWindow
            )) else { return }
            target = chosen
            format = ImageFormat(fileExtension: chosen.pathExtension) ?? format
            settings.lastSaveAsDirectory = chosen.deletingLastPathComponent()
        } else {
            switch intent {
            case .overwrite(let url, let fmt):
                target = url
                format = fmt
            case .newFile(let dir, let name):
                target = dir.appendingPathComponent(name)
                format = settings.defaultFormat
            }
        }

        // Re-encode when the destination isn't PNG, so a .jpg keeps being a .jpg.
        var bytes = data
        if format != .png {
            bytes = await Task.detached {
                (try? ImageCodec.decode(data)).flatMap { try? ImageCodec.encode($0, as: format) } ?? data
            }.value
        }

        do {
            if case .newFile(let dir, let name) = intent, !saveAs {
                // Collision-safe for brand new files; Save As and overwrite go
                // to the exact path the user confirmed.
                target = try CaptureSaver().save(bytes, fileName: name, to: dir)
            } else {
                try CaptureSaver().write(bytes, to: target)
            }
        } catch {
            lastError = error.localizedDescription
            return
        }

        let size = await Task.detached {
            (try? ImageCodec.decode(bytes)).map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        }.value
        try? await captureService.upsertExisting(HistoryEntry(
            fileURL: target,
            createdAt: Date(),
            mode: .region,
            pixelWidth: Int(size.width),
            pixelHeight: Int(size.height),
            kind: .image
        ))

        // The bytes at this path changed — drop derived data keyed off it.
        await ThumbnailLoader.shared.invalidate(target)
        await textIndexer.forget(target)

        // The editor adopts the file it just wrote, so the next ⌘S replaces it.
        editor?.markSaved(url: target)

        await refreshRecent()
        indexCapturesForSearch()
        hud.show(message: String(localized: "Saved"), thumbnail: NSImage(data: bytes))
    }

    // MARK: - State

    func refreshRecent() async {
        let entries = (try? await captureService.recentHistory(limit: 200)) ?? []
        recent = entries
        await refreshMetadata(for: entries)
    }

    /// Loads note/tag metadata so the dashboard can show and filter by tag.
    ///
    /// Resolves **every** entry in each index — not just the ones inside the
    /// recent-history window — because the sidebar's tag list is built from the
    /// whole index. Without this, selecting a tag whose captures are older than
    /// the window showed an empty grid while the sidebar insisted the tag
    /// existed. Works across all location modes, since key semantics differ:
    /// hidden/visible keys are file names relative to the index's own folder,
    /// custom keys are absolute paths.
    private func refreshMetadata(for entries: [HistoryEntry]) async {
        var indexURLs = Set(entries.compactMap { $0.fileURL.map { metadataLocator(for: $0).indexURL } })
        // Always load the active index so its tags populate the sidebar even
        // before any of its captures appear in recent history.
        indexURLs.insert(primaryMetadataIndexURL())

        var byURL: [URL: CaptureMetadata] = [:]
        var tags = Set<String>()
        for indexURL in indexURLs {
            let index = await metadataStore.index(at: indexURL)
            for (key, meta) in index.items {
                // Only count a tag once its file actually resolves — otherwise
                // an unresolvable key contributes a sidebar tag that shows an
                // empty grid, the exact symptom this set out to fix.
                guard let fileURL = resolveMetadataKey(key, in: indexURL) else { continue }
                byURL[fileURL] = meta
                if let tag = meta.tag, !tag.isEmpty { tags.insert(tag) }
            }
        }
        captureMeta = byURL
        knownTags = tags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        // Resolve which tagged files still exist ONCE per refresh, off the main
        // actor. `entries(taggedWith:)` is read from several places in every
        // dashboard render, so it must not hit the filesystem itself.
        let taggedURLs = byURL.filter { $0.value.tag?.isEmpty == false }.map(\.key)
        existingTaggedURLs = await Task.detached {
            Set(taggedURLs.filter { FileManager.default.fileExists(atPath: $0.path) })
        }.value
    }

    /// Inverse of `metadataLocator`: turns a stored index key back into the file
    /// it describes.
    private func resolveMetadataKey(_ key: String, in indexURL: URL) -> URL? {
        switch settings.metadataLocation {
        case .hidden, .visible:
            // Key is a bare file name, relative to the index's own directory.
            // Reject a path — a shared index previously written in `.custom`
            // mode holds absolute keys, which would otherwise resolve to
            // nonsense like `…/Pictures/AIShot/Users/me/Pictures/a.png`.
            guard !key.contains("/") else { return nil }
            return indexURL.deletingLastPathComponent()
                .appendingPathComponent(key).standardizedFileURL
        case .custom:
            // Key is an absolute path.
            guard key.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: key).standardizedFileURL
        }
    }

    /// Every capture carrying `tag`, including ones older than the recent
    /// window (synthesized from the metadata index so tag browsing is complete).
    /// Pure in-memory: existence was resolved during `refreshMetadata`, so this
    /// is safe to call repeatedly from a SwiftUI body.
    func entries(taggedWith tag: String) -> [HistoryEntry] {
        var results = recent.filter { metadata(for: $0)?.tag == tag }
        let known = Set(results.compactMap { $0.fileURL?.standardizedFileURL })

        let extra = captureMeta
            .filter { $0.value.tag == tag && !known.contains($0.key) }
            .keys
            .filter { existingTaggedURLs.contains($0) }
            .map(Self.synthesizedEntry(for:))

        results.append(contentsOf: extra)
        return results.sorted { $0.createdAt > $1.createdAt }
    }

    /// Builds a history entry for a tagged file that predates the recent
    /// window. Pixel size is unknown without decoding the file, so it's left at
    /// zero and the UI omits the dimension label.
    private static func synthesizedEntry(for url: URL) -> HistoryEntry {
        // FileManager rather than URL.resourceValues, which caches per instance.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return HistoryEntry(
            // Stable across refreshes so SwiftUI selection doesn't jump.
            id: deterministicID(for: url),
            fileURL: url,
            createdAt: attributes?[.modificationDate] as? Date ?? .distantPast,
            // Unknown — the UI gates the mode badge on `pixelWidth > 0` so this
            // placeholder is never presented as fact.
            mode: .region,
            pixelWidth: 0,
            pixelHeight: 0,
            kind: kind(for: url)
        )
    }

    /// A UUID derived from the file path, so a synthesized entry keeps the same
    /// identity every time it's rebuilt. Uses a stable digest rather than
    /// `Hasher`, whose seed is randomized per process launch.
    private static func deterministicID(for url: URL) -> UUID {
        let digest = Array(SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).prefix(16))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3],
                           digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11],
                           digest[12], digest[13], digest[14], digest[15]))
    }

    func refreshPermissions() async {
        var map: [Permission: PermissionStatus] = [:]
        for permission in Permission.allCases {
            map[permission] = await permissionsChecker.status(of: permission)
        }
        permissions = map
    }

    func request(_ permission: Permission) {
        Task {
            _ = await permissionsChecker.request(permission)
            await refreshPermissions()
        }
    }

    func saveSettings() {
        try? settingsStore.save(settings)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
