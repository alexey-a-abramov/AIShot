import Foundation
import AIShotCore

/// User-configurable settings, surfaced in the Settings window and honored by
/// the capture pipeline and MCP server.
public struct AppSettings: Sendable, Codable, Equatable {
    /// Directory new captures are written to.
    public var saveDirectory: URL
    public var defaultFormat: ImageFormat
    /// Filename template. Tokens: `{date}`, `{time}`, `{app}`, `{seq}`.
    public var fileNameTemplate: String
    public var copyToClipboard: Bool
    public var showNotification: Bool
    public var playSound: Bool
    public var launchAtLogin: Bool
    /// Whether the embedded MCP server is running.
    public var mcpEnabled: Bool
    /// Loopback port for the in-app MCP HTTP transport.
    public var mcpPort: Int
    /// Safety gate: require an explicit user confirmation before MCP-driven
    /// synthetic input (clicks/typing) or app switching. Defaults to `true`.
    public var mcpRequireConfirmationForInput: Bool

    public init(
        saveDirectory: URL,
        defaultFormat: ImageFormat = .png,
        fileNameTemplate: String = "AIShot {date} at {time}",
        copyToClipboard: Bool = true,
        showNotification: Bool = true,
        playSound: Bool = true,
        launchAtLogin: Bool = false,
        mcpEnabled: Bool = true,
        mcpPort: Int = 47600,
        mcpRequireConfirmationForInput: Bool = true
    ) {
        self.saveDirectory = saveDirectory
        self.defaultFormat = defaultFormat
        self.fileNameTemplate = fileNameTemplate
        self.copyToClipboard = copyToClipboard
        self.showNotification = showNotification
        self.playSound = playSound
        self.launchAtLogin = launchAtLogin
        self.mcpEnabled = mcpEnabled
        self.mcpPort = mcpPort
        self.mcpRequireConfirmationForInput = mcpRequireConfirmationForInput
    }

    /// Sensible defaults: save to `~/Pictures/AIShot`, PNG, copy to clipboard,
    /// notify, and require confirmation for risky MCP actions.
    public static var `default`: AppSettings {
        let pictures = FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return AppSettings(saveDirectory: pictures.appendingPathComponent("AIShot", isDirectory: true))
    }
}

/// Persists `AppSettings`. Phase P1 backs this with `Defaults`/`UserDefaults`.
public protocol SettingsStore: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}
