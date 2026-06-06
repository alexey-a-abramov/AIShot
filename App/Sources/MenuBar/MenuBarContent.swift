import SwiftUI

/// Contents of the menu-bar dropdown. Actions are stubbed until Phase P1a wires
/// them to the capture engine; the real shortcuts are registered globally via
/// KeyboardShortcuts (these accelerators are in-menu hints only).
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capture Region…") { capture(.region) }
        Button("Capture Window…") { capture(.window) }
        Button("Capture Full Screen") { capture(.display) }

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

    private func capture(_ mode: CaptureMenuAction) {
        // TODO(P1a): forward to the capture coordinator.
        _ = mode
    }
}

private enum CaptureMenuAction {
    case region, window, display
}
