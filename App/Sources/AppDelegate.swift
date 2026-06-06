import AppKit

/// Owns app-lifetime services. Phase P1 starts the capture engine, the embedded
/// MCP server, and global hotkeys here; for now it only configures the agent UI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon. The dashboard still opens as a window.
        NSApp.setActivationPolicy(.accessory)

        // TODO(P1a): start `ScreenCaptureKitEngine` and request Screen Recording.
        // TODO(P1b): start the embedded MCP server (loopback HTTP + stdio bridge).
        // TODO(P1a): register global hotkeys via KeyboardShortcuts and load AppSettings.
    }
}
