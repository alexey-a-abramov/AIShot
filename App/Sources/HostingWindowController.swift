import AppKit
import SwiftUI

/// Hosts a SwiftUI view in a reusable AppKit window. Menu-bar (`.accessory`)
/// apps can't reliably surface SwiftUI `Window`/`Settings` scenes, so Settings
/// and the Dashboard are presented this way — `makeKeyAndOrderFront` + activate
/// brings them to the front immediately.
///
/// The content view is built once (on first `show()`) and reused; the hosted
/// views stay current via `@EnvironmentObject`/`@Published`.
@MainActor
final class HostingWindowController<Content: View> {
    private var window: NSWindow?
    private let title: String
    private let size: NSSize
    private let minSize: NSSize?
    private let autosaveName: String?
    private let resizable: Bool
    private let makeContent: () -> Content

    /// - Parameters:
    ///   - size: the default content size used the first time the window opens.
    ///   - minSize: the smallest content size the user can resize down to, so a
    ///     classic resizable window never collapses into a broken layout.
    ///   - autosaveName: when set, the window remembers its size and position
    ///     across launches (standard macOS behavior).
    ///   - resizable: pass `false` for a fixed-size panel such as About, which
    ///     sizes itself to its content and looks broken when stretched.
    init(
        title: String,
        size: NSSize,
        minSize: NSSize? = nil,
        autosaveName: String? = nil,
        resizable: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.size = size
        self.minSize = minSize
        self.autosaveName = autosaveName
        self.resizable = resizable
        self.makeContent = content
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeContent())
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = resizable
                ? [.titled, .closable, .miniaturizable, .resizable]
                : [.titled, .closable]
            window.setContentSize(size)
            if let minSize { window.contentMinSize = minSize }
            window.isReleasedWhenClosed = false
            window.center()
            // Restores the saved frame if one exists (overriding the default
            // size/center above), and persists future moves and resizes.
            if let autosaveName { window.setFrameAutosaveName(autosaveName) }
            // Recenter if a restored frame landed off-screen (e.g. it was saved
            // on a display that's no longer connected).
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
                window.center()
            }
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
