import AppKit

/// Shows captured images in floating, always-on-top, draggable windows
/// (CleanShot-style "pin to screen").
@MainActor
final class PinnedWindowController {
    private var windows: [NSWindow] = []

    func pin(_ image: NSImage) {
        let pointSize = image.size
        let maxDimension: CGFloat = 520
        let scale = min(1, maxDimension / max(pointSize.width, pointSize.height, 1))
        let width = max(120, pointSize.width * scale)
        let height = max(90, pointSize.height * scale)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Pinned"
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = imageView

        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }
}
