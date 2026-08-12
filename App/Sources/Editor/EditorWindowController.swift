import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Hosts the SwiftUI annotation editor in a reusable AppKit window so it can be
/// opened programmatically (e.g. automatically after a capture).
@MainActor
final class EditorWindowController {
    private var window: NSWindow?
    private var currentEditor: EditorModel?

    func present(imageData: Data, pixelSize: CGSize, sourceURL: URL? = nil, app: AppModel) {
        let editor = EditorModel(imageData: imageData, pixelSize: pixelSize, sourceURL: sourceURL)
        let hosting = NSHostingController(
            rootView: AnnotationEditorView(editor: editor).environmentObject(app)
        )

        // Reusing the window would silently discard annotations in progress, so
        // open a second one when the current editor has unsaved work.
        let reusable = currentEditor?.hasUnsavedChanges != true
        let window = (reusable ? self.window : nil) ?? makeWindow()
        window.contentViewController = hosting
        window.representedURL = sourceURL
        window.title = sourceURL?.lastPathComponent ?? String(localized: "Edit Screenshot")
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        self.currentEditor = editor
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
