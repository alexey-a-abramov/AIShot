import SwiftUI

/// AIShot is a menu-bar agent. `MenuBarExtra` is the primary surface; the
/// Dashboard ("admin") window and Settings open on demand.
@main
struct AIShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("AIShot", systemImage: "camera.viewfinder") {
            MenuBarContent().environmentObject(model)
        }
        .menuBarExtraStyle(.menu)

        Window("AIShot", id: AIShotWindow.dashboard.rawValue) {
            DashboardView().environmentObject(model)
        }
        .defaultSize(width: 820, height: 560)

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

/// Identifiers for openable windows.
enum AIShotWindow: String {
    case dashboard
}
