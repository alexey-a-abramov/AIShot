import AppKit
import Combine
import CoreGraphics
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

    @Published var settings: AppSettings
    @Published var recent: [HistoryEntry] = []
    @Published var permissions: [Permission: PermissionStatus] = [:]
    @Published var lastError: String?

    /// The most recent capture, available for "Edit Last Capture".
    @Published private(set) var lastCapture: CapturedImage?

    let captureService: CaptureService
    private let settingsStore: UserDefaultsSettingsStore
    private let permissionsChecker = SystemPermissions()
    private let overlay = SelectionOverlayController()
    private let recognizer = TextRecognizer()
    private let recorder = ScreenRecorder()
    private let scroller = ScrollingCapture()
    private let pinController = PinnedWindowController()
    private let hud = CaptureHUDController()
    private let editorWindow = EditorWindowController()
    private let updater = UpdaterController()

    private lazy var settingsWindow = HostingWindowController(
        title: "Settings", size: NSSize(width: 560, height: 480)
    ) { [unowned self] in AnyView(SettingsView().environmentObject(self)) }

    private lazy var dashboardWindow = HostingWindowController(
        title: "AIShot", size: NSSize(width: 860, height: 580)
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
    }

    // MARK: - Capture actions

    func captureRegion() {
        if settings.freezeBeforeRegionSelect {
            Task { await beginFrozenRegionCapture() }
        } else {
            overlay.begin { [weak self] selection in
                guard let self, let selection else { return }
                Task { @MainActor in
                    await self.run(CaptureRequest(
                        mode: .region,
                        displayID: selection.displayID,
                        rect: selection.rect,
                        includeCursor: self.settings.includeCursor,
                        format: self.settings.defaultFormat
                    ))
                }
            }
        }
    }

    /// Freeze-frame region capture: snapshot every display into memory, let the
    /// user select against the frozen image, then crop & deliver (or discard on
    /// cancel — nothing is captured if the user cancels).
    private func beginFrozenRegionCapture() async {
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
            overlay.begin(frozen: images) { [weak self] selection in
                guard let self, let selection, let frozen = captures[selection.displayID] else { return }
                Task { @MainActor in await self.deliverFrozenRegion(frozen, selection: selection) }
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    private func deliverFrozenRegion(_ frozen: CapturedImage, selection: RegionSelection) async {
        guard let cropped = Self.crop(frozen, toPointRect: selection.rect, format: settings.defaultFormat) else {
            lastError = "Could not crop the selected region."
            return
        }
        do {
            let outcome = try await captureService.deliver(cropped, mode: .region)
            await handleOutcome(outcome)
        } catch {
            lastError = String(describing: error)
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
        Task {
            await run(CaptureRequest(
                mode: .display, displayID: CGMainDisplayID(),
                includeCursor: settings.includeCursor, format: settings.defaultFormat
            ))
        }
    }

    func captureFrontWindow() {
        Task {
            let windows = (try? await captureService.windows()) ?? []
            guard let target = windows.first(where: { $0.isOnScreen && !$0.title.isEmpty }) else {
                lastError = "No window available to capture."
                return
            }
            await run(CaptureRequest(
                mode: .window, windowID: target.id,
                includeCursor: settings.includeCursor, format: settings.defaultFormat
            ))
        }
    }

    /// Region-select, capture, OCR, and copy the recognized text to the clipboard.
    func captureTextOCR() {
        overlay.begin { [weak self] selection in
            guard let self, let selection else { return }
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
    func scrollingCapture() {
        overlay.begin { [weak self] selection in
            guard let self, let selection else { return }
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
                    lastError = "Saved recording: \(url.lastPathComponent)"
                } else {
                    let formatter = DateFormatter()
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

    /// Captures the main display, returning the saved file path (for App Intents).
    @discardableResult
    func captureFullScreenReturningPath() async -> String? {
        do {
            let outcome = try await captureService.performCapture(
                CaptureRequest(mode: .display, displayID: CGMainDisplayID(),
                               includeCursor: settings.includeCursor, format: settings.defaultFormat)
            )
            lastCapture = outcome.image
            await refreshRecent()
            return outcome.result.fileURL?.path
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    private func run(_ request: CaptureRequest) async {
        do {
            let outcome = try await captureService.performCapture(request)
            await handleOutcome(outcome)
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Shared post-capture handling: remember, refresh, feedback, open editor.
    private func handleOutcome(_ outcome: CaptureOutcome) async {
        lastCapture = outcome.image
        await refreshRecent()
        feedback(for: outcome)
        if settings.postCaptureAction == .openEditor {
            openEditor(imageData: outcome.image.data, pixelSize: outcome.image.pixelSize)
        }
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
    func openEditor(imageData: Data, pixelSize: CGSize) {
        editorWindow.present(imageData: imageData, pixelSize: pixelSize, app: self)
    }

    /// Opens the editor on the most recent capture.
    func editLastCapture() {
        guard let capture = lastCapture else { return }
        openEditor(imageData: capture.data, pixelSize: capture.pixelSize)
    }

    func openSettings() { settingsWindow.show() }
    func openDashboard() { dashboardWindow.show() }

    /// Saves and/or copies edited image bytes using the current settings.
    func export(_ data: Data, copy: Bool, save: Bool) async {
        if save {
            let name = FileNameFormatter(template: settings.fileNameTemplate)
                .fileName(format: .png, date: Date())
            _ = try? CaptureSaver().save(data, fileName: name, to: settings.saveDirectory)
            await refreshRecent()
        }
        if copy {
            try? await AppKitClipboard().copyImage(data)
        }
    }

    // MARK: - State

    func refreshRecent() async {
        recent = (try? await captureService.recentHistory(limit: 30)) ?? []
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
