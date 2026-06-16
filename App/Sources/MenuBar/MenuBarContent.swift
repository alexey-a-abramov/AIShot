import AppKit
import SwiftUI
import KeyboardShortcuts

/// Contents of the menu-bar dropdown, wired to `AppModel` actions. Each item
/// shows its currently-assigned global shortcut (configurable in Settings).
struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button { model.captureRegion() } label: { menuLabel("Capture Region…", .captureRegion) }
        Button { model.captureFrontWindow() } label: { menuLabel("Capture Window…", .captureWindow) }
        Button { model.captureFullScreen() } label: { menuLabel("Capture Full Screen", .captureFullScreen) }
        Button { model.captureTextOCR() } label: { menuLabel("Capture Text (OCR)", .captureText) }
        Button { model.scrollingCapture() } label: { menuLabel("Scrolling Capture", .scrollingCapture) }

        Divider()

        Button { model.pickColor() } label: { menuLabel("Pick Color", .pickColor) }
        Button { model.editLastCapture() } label: { menuLabel("Edit Last Capture", .editLastCapture) }
            .disabled(model.lastCapture == nil)
        Button { model.pinLastCapture() } label: { menuLabel("Pin Last Capture", .pinLastCapture) }
            .disabled(model.lastCapture == nil)
        Button("Beautify Last Capture") { model.beautifyLastCapture() }
            .disabled(model.lastCapture == nil)
        Button("Redact Last Capture") { model.redactLastCapture() }
            .disabled(model.lastCapture == nil)

        Divider()

        if model.isRecording {
            Button { model.toggleRecording() } label: { menuLabel("Stop Recording", .toggleRecording) }
        } else {
            Button { model.toggleRecording() } label: { menuLabel("Start Recording", .toggleRecording) }
        }

        Divider()

        Button("Open Dashboard") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: AIShotWindow.dashboard.rawValue)
        }
        Button("Settings…") { openSettingsWindow() }
        Button("Check for Updates…") { model.checkForUpdates() }

        Divider()

        Button("Quit AIShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// Activates the app (an accessory/menu-bar app isn't frontmost) and opens
    /// the Settings window, so it appears immediately rather than behind.
    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 14+ action for the SwiftUI `Settings` scene (was
        // `showPreferencesWindow:` pre-14). Deployment target is macOS 15.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// A menu title with its assigned global shortcut appended (e.g. "⌘⌥⇧4").
    @ViewBuilder
    private func menuLabel(_ title: LocalizedStringKey, _ name: KeyboardShortcuts.Name) -> some View {
        if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
            Text(title) + Text(verbatim: "   \(shortcut)").foregroundColor(.secondary)
        } else {
            Text(title)
        }
    }
}
