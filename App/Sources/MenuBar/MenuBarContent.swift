import SwiftUI

/// Contents of the menu-bar dropdown, wired to `AppModel` actions.
struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capture Region…") { model.captureRegion() }
        Button("Capture Window…") { model.captureFrontWindow() }
        Button("Capture Full Screen") { model.captureFullScreen() }
        Button("Capture Text (OCR)") { model.captureTextOCR() }
        Button("Scrolling Capture") { model.scrollingCapture() }

        Divider()

        Button("Pick Color") { model.pickColor() }
        Button("Edit Last Capture") {
            model.prepareEditorForLastCapture()
            openWindow(id: AIShotWindow.editor.rawValue)
        }
        .disabled(model.lastCapture == nil)
        Button("Pin Last Capture") { model.pinLastCapture() }
            .disabled(model.lastCapture == nil)
        Button("Beautify Last Capture") { model.beautifyLastCapture() }
            .disabled(model.lastCapture == nil)
        Button("Redact Last Capture") { model.redactLastCapture() }
            .disabled(model.lastCapture == nil)

        Divider()

        if model.isRecording {
            Button("Stop Recording") { model.toggleRecording() }
        } else {
            Button("Start Recording") { model.toggleRecording() }
        }

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
