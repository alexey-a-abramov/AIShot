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
    private let makeContent: () -> Content

    init(title: String, size: NSSize, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.size = size
        self.makeContent = content
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeContent())
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(size)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
