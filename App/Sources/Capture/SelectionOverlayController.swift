import AppKit
import CoreGraphics

/// A region selection on a specific display, in display-local **top-left** points
/// (ready to hand to the capture engine).
struct RegionSelection: Sendable {
    var displayID: CGDirectDisplayID
    var rect: CGRect
}

/// Presents a dimmed, draggable selection overlay across every screen, with a
/// crosshair, a live dimension readout, and an instruction hint. The first
/// completed drag (or Esc) finishes and tears down all overlays.
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
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
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

/// A borderless window that can still become key, so the selection view
/// receives keyboard events (Esc to cancel).
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The per-screen tracking view that draws the dimmed overlay, crosshair, and
/// selection rectangle with a live dimension badge.
private final class SelectionView: NSView {
    private let screen: NSScreen
    private let onFinish: (RegionSelection?) -> Void
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var mouseLocation: NSPoint?

    init(screen: NSScreen, onFinish: @escaping (RegionSelection?) -> Void) {
        self.screen = screen
        self.onFinish = onFinish
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point
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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        let dragging = currentRect.width >= 1 && currentRect.height >= 1

        if !dragging {
            NSBezierPath(rect: bounds).fill()
            drawCrosshair()
            drawHint(String(localized: "Drag to select an area  ·  Esc to cancel"))
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

        let scale = screen.backingScaleFactor
        let pixels = "\(Int(currentRect.width * scale)) × \(Int(currentRect.height * scale)) px"
        drawBadge(pixels, for: currentRect)
    }

    private func drawCrosshair() {
        guard let m = mouseLocation else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: m.x + 0.5, y: 0))
        path.line(to: NSPoint(x: m.x + 0.5, y: bounds.height))
        path.move(to: NSPoint(x: 0, y: m.y + 0.5))
        path.line(to: NSPoint(x: bounds.width, y: m.y + 0.5))
        path.stroke()
    }

    private func drawHint(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let size = string.size()
        let padX: CGFloat = 14, padY: CGFloat = 8
        let rect = NSRect(
            x: (bounds.width - (size.width + padX * 2)) / 2,
            y: bounds.height * 0.8,
            width: size.width + padX * 2,
            height: size.height + padY * 2
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        string.draw(at: NSPoint(x: rect.minX + padX, y: rect.minY + padY))
    }

    private func drawBadge(_ text: String, for rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let size = string.size()
        let padX: CGFloat = 7, padY: CGFloat = 4
        let width = size.width + padX * 2
        let height = size.height + padY * 2
        var x = rect.midX - width / 2
        x = max(2, min(x, bounds.width - width - 2))
        var y = rect.maxY + 6
        if y + height > bounds.height { y = rect.minY - height - 6 }
        if y < 0 { y = rect.minY + 6 }
        let badge = NSRect(x: x, y: y, width: width, height: height)
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5).fill()
        string.draw(at: NSPoint(x: badge.minX + padX, y: badge.minY + padY))
    }
}
