import SwiftUI

/// AIShot is a menu-bar agent. `MenuBarExtra` is the primary surface; the
/// dashboard ("admin") window and Settings open on demand.
@main
struct AIShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("AIShot", systemImage: "camera.viewfinder") {
            MenuBarContent()
        }
        .menuBarExtraStyle(.menu)

        Window("AIShot", id: AIShotWindow.dashboard.rawValue) {
            DashboardView()
        }
        .defaultSize(width: 760, height: 500)

        Settings {
            SettingsView()
        }
    }
}

/// Identifiers for openable windows.
enum AIShotWindow: String {
    case dashboard
}
