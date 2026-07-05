import AppKit
import SwiftUI
import KeyboardShortcuts
import AIShotPersistence

/// Contents of the menu-bar dropdown, wired to `AppModel` actions. Each item
/// shows its currently-assigned global shortcut (configurable in Settings).
struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.captureRegion() } label: { menuLabel("Capture Region…", .captureRegion) }
        Button { model.captureFrontWindow() } label: { menuLabel("Capture Window…", .captureWindow) }
        Button { model.captureFullScreen() } label: { menuLabel("Capture Full Screen", .captureFullScreen) }
        Button { model.captureAllDisplays() } label: { menuLabel("Capture All Displays", .captureAllDisplays) }
        Button { model.captureTextOCR() } label: { menuLabel("Capture Text (OCR)", .captureText) }
        Button { model.scrollingCapture() } label: { menuLabel("Scrolling Capture", .scrollingCapture) }

        Menu("Self-Timer") {
            Picker("Self-Timer", selection: $model.settings.captureDelay) {
                Text("Off").tag(0.0)
                Text("3 seconds").tag(3.0)
                Text("5 seconds").tag(5.0)
                Text("10 seconds").tag(10.0)
            }
        }

        Divider()

        Button { model.pickColor() } label: { menuLabel("Pick Color", .pickColor) }
        Button { model.editLastCapture() } label: { menuLabel("Edit Last Capture", .editLastCapture) }
            .disabled(model.lastCapture == nil)
        Button { model.pinLastCapture() } label: { menuLabel("Pin Last Capture", .pinLastCapture) }
            .disabled(model.lastCapture == nil)

        Divider()

        if model.isRecording {
            Button { model.toggleRecording() } label: { menuLabel("Stop Recording", .toggleRecording) }
        } else {
            Button { model.toggleRecording() } label: { menuLabel("Start Recording", .toggleRecording) }
            Menu("Recording Format") {
                Picker("Recording Format", selection: $model.settings.recordingFormat) {
                    Text("Video (.mp4)").tag(RecordingFormat.mp4)
                    Text("Animated GIF").tag(RecordingFormat.gif)
                }
            }
        }

        Divider()

        Button("Open Dashboard") { model.openDashboard() }
        Button("Settings…") { model.openSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button("Check for Updates…") { model.checkForUpdates() }

        Divider()

        Button("Quit AIShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
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
