import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Hosts the SwiftUI annotation editor in a reusable AppKit window so it can be
/// opened programmatically (e.g. automatically after a capture).
@MainActor
final class EditorWindowController {
    private var window: NSWindow?

    func present(imageData: Data, pixelSize: CGSize, app: AppModel) {
        let editor = EditorModel(imageData: imageData, pixelSize: pixelSize)
        let hosting = NSHostingController(
            rootView: AnnotationEditorView(editor: editor).environmentObject(app)
        )

        let window = self.window ?? makeWindow()
        window.contentViewController = hosting
        window.title = "Edit Screenshot"
        window.setContentSize(NSSize(width: 980, height: 680))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
