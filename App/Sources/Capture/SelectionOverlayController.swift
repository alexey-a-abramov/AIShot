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
    private var completion: ((CaptureSelectionResult?) -> Void)?
    /// A local key-event monitor that guarantees Esc cancels even if, for any
    /// reason (most commonly: capture triggered by a global hotkey while a
    /// different app was frontmost), an overlay window isn't yet key.
    private var keyMonitor: Any?
    /// Observers torn down alongside the windows, so a cancelled capture leaves
    /// nothing behind.
    private var lifetimeObservers: [NSObjectProtocol] = []

    /// - Parameter frozen: optional per-display snapshot images. When provided,
    ///   each overlay shows the frozen screenshot as its background (freeze-frame
    ///   mode) instead of the live screen.
    /// True while an overlay is on screen. Other actions check this so they
    /// can't fire underneath a capture.
    var isActive: Bool { !windows.isEmpty }

    func begin(
        frozen: [CGDirectDisplayID: NSImage]? = nil,
        _ completion: @escaping (CaptureSelectionResult?) -> Void
    ) {
        cancel()
        self.completion = completion

        // Activate BEFORE creating/keying the overlay windows. Capture is most
        // often triggered by a global hotkey while another app is frontmost;
        // requesting key-window status before this app is actually active is a
        // race that can leave keyboard focus (and Esc) with the other app.
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let view = SelectionView(screen: screen, background: frozen?[Self.displayID(of: screen)]) { [weak self] selection in
                self?.finish(selection.map { CaptureSelectionResult(selection: $0) })
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

        // A display reconfiguration invalidates every overlay's geometry, and
        // losing activation means the user is somewhere else entirely. Losing
        // the capture beats leaving an un-dismissable full-screen dim.
        for name in [NSApplication.didChangeScreenParametersNotification,
                     NSApplication.didResignActiveNotification] {
            lifetimeObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.cancel() }
                }
            )
        }

        // Belt-and-braces: even if a window somehow isn't key/first-responder,
        // this local monitor still sees Esc as long as this app is frontmost.
        // Scoped to our own overlay windows so Esc typed into some other AIShot
        // window (e.g. Settings, if it happens to be open) isn't hijacked.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event } // Esc
            guard event.window == nil || self.windows.contains(where: { $0 === event.window }) else {
                return event
            }
            self.finish(nil)
            return nil
        }
    }

    func cancel() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        lifetimeObservers.forEach(NotificationCenter.default.removeObserver)
        lifetimeObservers.removeAll()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        // Resolve any still-pending completion (e.g. a second capture starting
        // while a first selection is in flight) so its caller — often an async
        // continuation — is never left hanging.
        if let pending = completion {
            completion = nil
            pending(nil)
        }
    }

    private func finish(_ result: CaptureSelectionResult?) {
        let completion = self.completion
        self.completion = nil
        cancel()
        completion?(result)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
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
    private let background: NSImage?
    private let onFinish: (RegionSelection?) -> Void
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var mouseLocation: NSPoint?

    init(screen: NSScreen, background: NSImage?, onFinish: @escaping (RegionSelection?) -> Void) {
        self.screen = screen
        self.background = background
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
        // Freeze-frame mode: paint the captured snapshot so the screen appears
        // frozen while selecting; the dim/selection draw on top.
        background?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)

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
