import Foundation

/// The catalog of tools the embedded MCP server exposes to local agents.
///
/// Raw values are the wire names agents call. `isPrivileged` marks tools that
/// drive synthetic input or app control — these are gated behind the
/// `mcpRequireConfirmationForInput` setting.
public enum MCPTool: String, Sendable, CaseIterable {
    // ── Read / enumerate ──
    case listDisplays = "list_displays"
    case listWindows = "list_windows"
    case listApps = "list_apps"
    case getHistory = "get_history"

    // ── Capture ──
    case captureRegion = "capture_region"
    case captureWindow = "capture_window"
    case captureDisplay = "capture_display"

    // ── Edit ──
    case annotate = "annotate"
    case beautify = "beautify"
    case redact = "redact"

    // ── Vision ──
    case locate = "locate"
    case ocr = "ocr"

    // ── Privileged: app control + synthetic input ──
    case switchApp = "switch_app"
    case click = "click"
    case typeText = "type_text"

    /// One-line, agent-facing description.
    public var summary: String {
        switch self {
        case .listDisplays: "List connected displays with id, frame, and scale."
        case .listWindows: "List on-screen windows with id, title, and owning app."
        case .listApps: "List running applications."
        case .getHistory: "Return recent captures from history."
        case .captureRegion: "Capture a rectangular region of a display; returns the image."
        case .captureWindow: "Capture a single window by id; returns the image."
        case .captureDisplay: "Capture a full display by id; returns the image."
        case .annotate: "Draw arrows/rectangles/text on an image and return the result."
        case .beautify: "Frame an image on a gradient background with padding and shadow."
        case .redact: "Auto-detect and blur sensitive text (emails, cards, IPs) in an image."
        case .locate: "Find on-screen UI by text or template; returns matching rects."
        case .ocr: "Recognize text in a display or region and return it."
        case .switchApp: "Bring an application to the foreground by bundle id."
        case .click: "Click at a screen coordinate (synthetic input)."
        case .typeText: "Type text into the focused app (synthetic input)."
        }
    }

    /// Whether the tool performs synthetic input or app control. Such tools are
    /// confirmation-gated by default.
    public var isPrivileged: Bool {
        switch self {
        case .switchApp, .click, .typeText: true
        default: false
        }
    }
}
