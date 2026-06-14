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
    /// Open the annotation editor automatically after an interactive capture.
    public var openEditorAfterCapture: Bool
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
        openEditorAfterCapture: Bool = true,
        launchAtLogin: Bool = false,
        mcpEnabled: Bool = false,
        mcpPort: Int = 47600,
        mcpRequireConfirmationForInput: Bool = true
    ) {
        self.saveDirectory = saveDirectory
        self.defaultFormat = defaultFormat
        self.fileNameTemplate = fileNameTemplate
        self.copyToClipboard = copyToClipboard
        self.showNotification = showNotification
        self.playSound = playSound
        self.openEditorAfterCapture = openEditorAfterCapture
        self.launchAtLogin = launchAtLogin
        self.mcpEnabled = mcpEnabled
        self.mcpPort = mcpPort
        self.mcpRequireConfirmationForInput = mcpRequireConfirmationForInput
    }

    /// Resilient decoding: unknown/missing keys fall back to defaults so adding
    /// a setting never invalidates a user's stored configuration.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        saveDirectory = try container.decodeIfPresent(URL.self, forKey: .saveDirectory) ?? fallback.saveDirectory
        defaultFormat = try container.decodeIfPresent(ImageFormat.self, forKey: .defaultFormat) ?? fallback.defaultFormat
        fileNameTemplate = try container.decodeIfPresent(String.self, forKey: .fileNameTemplate) ?? fallback.fileNameTemplate
        copyToClipboard = try container.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? fallback.copyToClipboard
        showNotification = try container.decodeIfPresent(Bool.self, forKey: .showNotification) ?? fallback.showNotification
        playSound = try container.decodeIfPresent(Bool.self, forKey: .playSound) ?? fallback.playSound
        openEditorAfterCapture = try container.decodeIfPresent(Bool.self, forKey: .openEditorAfterCapture) ?? fallback.openEditorAfterCapture
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        mcpEnabled = try container.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? fallback.mcpEnabled
        mcpPort = try container.decodeIfPresent(Int.self, forKey: .mcpPort) ?? fallback.mcpPort
        mcpRequireConfirmationForInput = try container.decodeIfPresent(Bool.self, forKey: .mcpRequireConfirmationForInput) ?? fallback.mcpRequireConfirmationForInput
    }

    /// Sensible defaults: save to `~/Pictures/AIShot`, PNG, copy to clipboard,
    /// notify, open the editor after capture, and confirm risky MCP actions.
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
