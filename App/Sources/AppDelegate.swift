import AppKit
import UserNotifications
import KeyboardShortcuts

/// Owns app-lifetime services: activation policy, global hotkeys, and the
/// notification category/delegate wiring.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerHotkeys()
        registerNotifications()
        Task {
            await AppModel.shared.refreshPermissions()
            await AppModel.shared.refreshRecent()
        }
    }

    private func registerHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .captureRegion) {
            Task { @MainActor in AppModel.shared.captureRegion() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) {
            Task { @MainActor in AppModel.shared.captureFrontWindow() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureFullScreen) {
            Task { @MainActor in AppModel.shared.captureFullScreen() }
        }
    }

    private func registerNotifications() {
        let center = UNUserNotificationCenter.current()
        let copy = UNNotificationAction(identifier: UserNotificationPresenter.copyActionIdentifier, title: "Copy")
        let reveal = UNNotificationAction(identifier: UserNotificationPresenter.revealActionIdentifier, title: "Reveal in Finder")
        let category = UNNotificationCategory(
            identifier: UserNotificationPresenter.categoryIdentifier,
            actions: [copy, reveal],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
        center.delegate = self
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let path = info["fileURL"] as? String else { return }
        let url = URL(fileURLWithPath: path)
        let action = response.actionIdentifier

        if action == UserNotificationPresenter.copyActionIdentifier {
            if let data = try? Data(contentsOf: url) {
                try? await AppKitClipboard().copyImage(data)
            }
            return
        }
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
