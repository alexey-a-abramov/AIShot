import AppKit
import CoreGraphics

/// A region selection on a specific display, in display-local **top-left** points
/// (ready to hand to the capture engine).
struct RegionSelection: Sendable {
    var displayID: CGDirectDisplayID
    var rect: CGRect
}

/// Presents a dimmed, draggable selection overlay across every screen. The
/// first completed drag (or Esc) finishes and tears down all overlays.
@MainActor
final class SelectionOverlayController {
    private var windows: [NSWindow] = []
    private var completion: ((RegionSelection?) -> Void)?

    func begin(_ completion: @escaping (RegionSelection?) -> Void) {
        cancel()
        self.completion = completion

        for screen in NSScreen.screens {
            let view = SelectionView(screen: screen) { [weak self] result in
                self?.finish(result)
            }
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func cancel() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func finish(_ result: RegionSelection?) {
        let completion = self.completion
        self.completion = nil
        cancel()
        completion?(result)
    }
}

/// The per-screen tracking view that draws the dimmed overlay and selection.
private final class SelectionView: NSView {
    private let screen: NSScreen
    private let onFinish: (RegionSelection?) -> Void
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero

    init(screen: NSScreen, onFinish: @escaping (RegionSelection?) -> Void) {
        self.screen = screen
        self.onFinish = onFinish
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { startPoint = nil }
        guard currentRect.width >= 2, currentRect.height >= 2 else {
            onFinish(nil)
            return
        }
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = number?.uint32Value ?? CGMainDisplayID()
        // Convert from this screen's bottom-left view space to display-local top-left.
        let topLeft = CGRect(
            x: currentRect.minX,
            y: bounds.height - currentRect.maxY,
            width: currentRect.width,
            height: currentRect.height
        )
        onFinish(RegionSelection(displayID: displayID, rect: topLeft))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        if currentRect.width < 1 || currentRect.height < 1 {
            NSBezierPath(rect: bounds).fill()
            return
        }
        // Dim everything except the selection (four surrounding rects).
        let surrounds = [
            NSRect(x: 0, y: currentRect.maxY, width: bounds.width, height: bounds.maxY - currentRect.maxY),
            NSRect(x: 0, y: 0, width: bounds.width, height: currentRect.minY),
            NSRect(x: 0, y: currentRect.minY, width: currentRect.minX, height: currentRect.height),
            NSRect(x: currentRect.maxX, y: currentRect.minY, width: bounds.maxX - currentRect.maxX, height: currentRect.height),
        ]
        surrounds.forEach { NSBezierPath(rect: $0).fill() }

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: currentRect)
        border.lineWidth = 2
        border.stroke()
    }
}
