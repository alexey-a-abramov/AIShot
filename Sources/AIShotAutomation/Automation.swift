import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Vision
import AIShotCore
import AIShotShared

/// A running application, for the `list_apps` / `switch_app` MCP tools.
public struct AppInfo: Sendable, Identifiable, Codable, Equatable {
    /// Bundle identifier (the stable `id`).
    public var id: String
    public var name: String
    public var processIdentifier: Int32
    public var isActive: Bool

    public init(id: String, name: String, processIdentifier: Int32, isActive: Bool) {
        self.id = id
        self.name = name
        self.processIdentifier = processIdentifier
        self.isActive = isActive
    }
}

/// Enumerate and focus applications (backed by `NSWorkspace`).
public protocol AppSwitching: Sendable {
    func runningApps() async throws -> [AppInfo]
    func frontmostApp() async throws -> AppInfo?
    func activate(bundleID: String) async throws
}

public enum MouseButton: String, Sendable, Codable {
    case left, right, center
}

/// Synthetic mouse/keyboard input (backed by `CGEvent`). Requires the
/// Accessibility permission and a non-sandboxed build.
public protocol InputAutomating: Sendable {
    func move(to point: CGPoint) async throws
    func click(at point: CGPoint, button: MouseButton) async throws
    func type(text: String) async throws
}

/// A request to locate UI on screen, by recognized text and/or template image.
public struct LocatorQuery: Sendable, Equatable {
    public var text: String?
    /// PNG bytes of a template to match, if doing image matching.
    public var templatePNG: Data?
    public init(text: String? = nil, templatePNG: Data? = nil) {
        self.text = text
        self.templatePNG = templatePNG
    }
}

/// A located region with a confidence score in `0...1`.
public struct LocatorMatch: Sendable, Equatable, Codable {
    public var rect: CGRect
    public var confidence: Double
    /// Recognized text for the match, when located by text.
    public var text: String?
    public init(rect: CGRect, confidence: Double, text: String? = nil) {
        self.rect = rect
        self.confidence = confidence
        self.text = text
    }
}

/// Find on-screen elements for vision-targeted clicks (backed by Vision OCR /
/// template matching).
public protocol ElementLocating: Sendable {
    func locate(_ query: LocatorQuery, inScreenshotPNG png: Data) async throws -> [LocatorMatch]
}

/// Accessibility + CGEvent + NSWorkspace implementation.
///
/// App switching uses `NSWorkspace` (no special permission). Synthetic input
/// uses `CGEvent.post`, which requires the Accessibility permission at runtime
/// and a non-sandboxed build.
public actor AutomationEngine: AppSwitching, InputAutomating {
    public init() {}

    // MARK: AppSwitching

    public func runningApps() async throws -> [AppInfo] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app -> AppInfo? in
                guard let bundle = app.bundleIdentifier else { return nil }
                return AppInfo(
                    id: bundle,
                    name: app.localizedName ?? bundle,
                    processIdentifier: app.processIdentifier,
                    isActive: app.isActive
                )
            }
        }
    }

    public func frontmostApp() async throws -> AppInfo? {
        await MainActor.run {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  let bundle = app.bundleIdentifier else { return nil }
            return AppInfo(
                id: bundle,
                name: app.localizedName ?? bundle,
                processIdentifier: app.processIdentifier,
                isActive: app.isActive
            )
        }
    }

    public func activate(bundleID: String) async throws {
        let activated = await MainActor.run { () -> Bool in
            guard let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == bundleID }) else { return false }
            return app.activate(options: [.activateAllWindows])
        }
        if !activated { throw AIShotError.targetNotFound("app \(bundleID)") }
    }

    // MARK: InputAutomating

    public func move(to point: CGPoint) async throws {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    public func click(at point: CGPoint, button: MouseButton) async throws {
        let (down, up, cgButton) = Self.mapButton(button)
        CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: point, mouseButton: cgButton)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: cgButton)?
            .post(tap: .cghidEventTap)
    }

    public func type(text: String) async throws {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up?.post(tap: .cghidEventTap)
    }

    private static func mapButton(_ button: MouseButton) -> (CGEventType, CGEventType, CGMouseButton) {
        switch button {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        case .center: (.otherMouseDown, .otherMouseUp, .center)
        }
    }
}

/// Vision-backed element locator: OCRs the screenshot and returns rects (in
/// top-left pixel coordinates) for text matching the query.
public actor VisionElementLocator: ElementLocating {
    public init() {}

    public func locate(_ query: LocatorQuery, inScreenshotPNG png: Data) async throws -> [LocatorMatch] {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIShotError.invalidRequest("locate: undecodable image")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let needle = query.text?.lowercased()
        return (request.results ?? []).compactMap { observation -> LocatorMatch? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            if let needle, !needle.isEmpty, !candidate.string.lowercased().contains(needle) { return nil }
            let box = observation.boundingBox // normalized, bottom-left origin
            let rect = CGRect(
                x: box.minX * width,
                y: (1 - box.maxY) * height,
                width: box.width * width,
                height: box.height * height
            )
            return LocatorMatch(rect: rect, confidence: Double(candidate.confidence), text: candidate.string)
        }
    }
}
