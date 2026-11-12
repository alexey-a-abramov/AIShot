import Foundation
import OSLog
import AIShotShared
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
        let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Screenshot captured"
        content.body = result.fileURL?.lastPathComponent ?? "Copied to clipboard"
        content.categoryIdentifier = Self.categoryIdentifier
        if let url = result.fileURL {
            content.userInfo = ["fileURL": url.path]
            // Attach a throwaway COPY, never the capture itself.
            //
            // UNNotificationAttachment takes ownership of the file it is given:
            // the system MOVES it into the notification store and deletes it
            // when the notification goes away. Handing it the real capture
            // silently destroys the screenshot the user just took, leaving a
            // history row pointing at nothing.
            if let copy = Self.temporaryCopy(of: url),
               let attachment = try? UNNotificationAttachment(identifier: result.id.uuidString, url: copy) {
                content.attachments = [attachment]
            }
        }
        let request = UNNotificationRequest(identifier: result.id.uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Copies a capture into a unique temporary directory for the notification
    /// to consume. Returns nil if the copy fails, in which case the
    /// notification is simply posted without a thumbnail.
    private static func temporaryCopy(of url: URL) -> URL? {
        let log = Logger.aishot("notifications")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIShotNotification/" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            log.error("could not stage a notification thumbnail: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
