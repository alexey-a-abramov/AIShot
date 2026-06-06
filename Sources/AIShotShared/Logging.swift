import Foundation
import OSLog

/// Top-level constants shared across the app and engine.
public enum AIShot {
    /// Bundle identifier — also the logging subsystem and `UserDefaults` scope.
    public static let bundleID = "com.aishot.app"

    /// Marketing name.
    public static let appName = "AIShot"
}

public extension Logger {
    /// Creates a logger in the AIShot subsystem for the given category, e.g.
    /// `Logger.aishot("capture")`.
    static func aishot(_ category: String) -> Logger {
        Logger(subsystem: AIShot.bundleID, category: category)
    }
}

/// Privacy-sensitive macOS capabilities the app depends on (TCC-gated).
public enum Permission: String, Sendable, CaseIterable, Codable {
    /// Required for ScreenCaptureKit capture.
    case screenRecording
    /// Required for synthetic input (clicks/keys) and reading other apps' UI.
    case accessibility
    /// Required to post capture notifications.
    case notifications
}

/// Current authorization state of a `Permission`.
public enum PermissionStatus: String, Sendable, Codable {
    case granted
    case denied
    case notDetermined
    case restricted
}
