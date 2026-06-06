import CoreGraphics
import Foundation
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
/// Phase P1d implements app switching first (`NSWorkspace`, low risk), then
/// gated synthetic input (`CGEvent.post`) behind the
/// `mcpRequireConfirmationForInput` setting.
public actor AutomationEngine: AppSwitching, InputAutomating {
    public init() {}

    // MARK: AppSwitching
    public func runningApps() async throws -> [AppInfo] {
        throw AIShotError.notImplemented("AutomationEngine.runningApps (P1d)")
    }
    public func frontmostApp() async throws -> AppInfo? {
        throw AIShotError.notImplemented("AutomationEngine.frontmostApp (P1d)")
    }
    public func activate(bundleID: String) async throws {
        throw AIShotError.notImplemented("AutomationEngine.activate (P1d)")
    }

    // MARK: InputAutomating
    public func move(to point: CGPoint) async throws {
        throw AIShotError.notImplemented("AutomationEngine.move (P1d)")
    }
    public func click(at point: CGPoint, button: MouseButton) async throws {
        throw AIShotError.notImplemented("AutomationEngine.click (P1d)")
    }
    public func type(text: String) async throws {
        throw AIShotError.notImplemented("AutomationEngine.type (P1d)")
    }
}

/// Vision-backed element locator.
public actor VisionElementLocator: ElementLocating {
    public init() {}
    public func locate(_ query: LocatorQuery, inScreenshotPNG png: Data) async throws -> [LocatorMatch] {
        throw AIShotError.notImplemented("VisionElementLocator.locate (P1d)")
    }
}
