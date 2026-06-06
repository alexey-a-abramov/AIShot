import AppKit
import Combine
import CoreGraphics
import SwiftUI
import AIShotCore
import AIShotCapture
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
    /// Image bytes handed to the editor window when it opens.
    @Published var editorImageData: Data?
    @Published var editorPixelSize: CGSize = .zero

    let captureService: CaptureService
    private let settingsStore: UserDefaultsSettingsStore
    private let permissionsChecker = SystemPermissions()
    private let overlay = SelectionOverlayController()

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
    }

    // MARK: - Capture actions

    func captureRegion() {
        overlay.begin { [weak self] selection in
            guard let self, let selection else { return }
            Task { @MainActor in
                await self.run(CaptureRequest(
                    mode: .region,
                    displayID: selection.displayID,
                    rect: selection.rect,
                    format: self.settings.defaultFormat
                ))
            }
        }
    }

    func captureFullScreen() {
        Task { await run(CaptureRequest(mode: .display, displayID: CGMainDisplayID(), format: settings.defaultFormat)) }
    }

    func captureFrontWindow() {
        Task {
            let windows = (try? await captureService.windows()) ?? []
            guard let target = windows.first(where: { $0.isOnScreen && !$0.title.isEmpty }) else {
                lastError = "No window available to capture."
                return
            }
            await run(CaptureRequest(mode: .window, windowID: target.id, format: settings.defaultFormat))
        }
    }

    private func run(_ request: CaptureRequest) async {
        do {
            let outcome = try await captureService.performCapture(request)
            lastCapture = outcome.image
            await refreshRecent()
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - Editor

    /// Loads the most recent capture into the editor state; the caller opens the
    /// editor window.
    func prepareEditorForLastCapture() {
        guard let capture = lastCapture else { return }
        editorImageData = capture.data
        editorPixelSize = capture.pixelSize
    }

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
}
