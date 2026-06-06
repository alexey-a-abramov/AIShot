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
            _ = try await captureService.performCapture(request)
            await refreshRecent()
        } catch {
            lastError = String(describing: error)
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
