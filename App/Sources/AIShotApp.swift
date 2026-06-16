import SwiftUI

/// AIShot is a menu-bar agent. `MenuBarExtra` is the only SwiftUI scene; the
/// Dashboard, Settings, and editor windows are AppKit-hosted (see
/// `HostingWindowController` / `EditorWindowController`) so they surface
/// reliably from an `.accessory` app.
@main
struct AIShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("AIShot", systemImage: "camera.viewfinder") {
            MenuBarContent().environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
    }
}
