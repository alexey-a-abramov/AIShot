import Foundation
import UserNotifications
import AIShotCore
import AIShotPersistence

/// Presents a capture notification with a thumbnail and Copy / Reveal actions.
struct UserNotificationPresenter: NotificationPresenting {
    static let categoryIdentifier = "capture"
    static let copyActionIdentifier = "copy"
    static let revealActionIdentifier = "reveal"

    func present(_ result: CaptureResult) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Screenshot captured"
        content.body = result.fileURL?.lastPathComponent ?? "Copied to clipboard"
        content.categoryIdentifier = Self.categoryIdentifier
        if let url = result.fileURL {
            content.userInfo = ["fileURL": url.path]
            if let attachment = try? UNNotificationAttachment(identifier: result.id.uuidString, url: url) {
                content.attachments = [attachment]
            }
        }
        let request = UNNotificationRequest(identifier: result.id.uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
