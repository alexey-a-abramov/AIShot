import SwiftUI

/// Contents of the menu-bar dropdown, wired to `AppModel` actions.
struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capture Region…") { model.captureRegion() }
        Button("Capture Window…") { model.captureFrontWindow() }
        Button("Capture Full Screen") { model.captureFullScreen() }

        Divider()

        Button("Open Dashboard") {
            openWindow(id: AIShotWindow.dashboard.rawValue)
        }
        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit AIShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
