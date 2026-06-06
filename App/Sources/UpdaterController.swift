import AppKit
import Foundation
import AIShotShared

/// Lightweight, dependency-free update check: fetches the appcast and offers a
/// download if a newer version exists. (Sparkle is the optional full-installer
/// path — see docs/RELEASING.md.)
@MainActor
final class UpdaterController {
    private let checker: UpdateChecker

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let feed = (Bundle.main.infoDictionary?["SUFeedURL"] as? String)
            .flatMap(URL.init(string:)) ?? URL(string: "https://aishot.app/appcast.xml")!
        checker = UpdateChecker(feedURL: feed, currentVersion: version)
    }

    func checkForUpdates() {
        Task {
            do {
                if let item = try await checker.check() {
                    present(item)
                } else {
                    info("You’re up to date.")
                }
            } catch {
                info("Update check failed: \(error.localizedDescription)")
            }
        }
    }

    private func present(_ item: AppcastItem) {
        let alert = NSAlert()
        alert.messageText = "Update available"
        alert.informativeText = "AIShot \(item.shortVersion ?? item.version) is available."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn, let url = item.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func info(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }
}
