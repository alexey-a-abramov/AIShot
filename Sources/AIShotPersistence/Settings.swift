import Foundation
import AIShotCore

/// What AIShot does automatically after an interactive capture.
public enum PostCaptureAction: String, Sendable, Codable, CaseIterable {
    /// Save and copy the image to the clipboard.
    case copyToClipboard
    /// Save and open the annotation editor.
    case openEditor
    /// Save only.
    case saveOnly
}

/// User-configurable settings, surfaced in the Settings window and honored by
/// the capture pipeline and MCP server.
public struct AppSettings: Sendable, Codable, Equatable {
    /// Directory new captures are written to.
    public var saveDirectory: URL
    public var defaultFormat: ImageFormat
    /// Filename template. Tokens: `{date}`, `{time}`, `{app}`, `{seq}`.
    public var fileNameTemplate: String
    /// Render the mouse cursor into captures by default.
    public var includeCursor: Bool
    /// Freeze the screen (snapshot first) before the region selection, so the
    /// content can't change while selecting. Disable for live selection.
    public var freezeBeforeRegionSelect: Bool
    /// The default action after an interactive capture.
    public var postCaptureAction: PostCaptureAction
    public var showNotification: Bool
    /// System sound played on capture, e.g. "Pop"/"Tink"; "None" disables it.
    public var captureSoundName: String
    public var launchAtLogin: Bool
    /// Whether the embedded MCP server is running.
    public var mcpEnabled: Bool
    /// Loopback port for the in-app MCP HTTP transport.
    public var mcpPort: Int
    /// Safety gate: require an explicit user confirmation before MCP-driven
    /// synthetic input (clicks/typing) or app switching. Defaults to `true`.
    public var mcpRequireConfirmationForInput: Bool
    /// Show the note + project-tag prompt after an interactive capture.
    public var captureMetadataEnabled: Bool
    /// Auto-apply `lastTag` to new captures without prompting (handy for a run
    /// of related screenshots). Toggled from the post-capture prompt.
    public var applyLastTag: Bool
    /// The most recently used project tag, offered as the default next time.
    public var lastTag: String?

    public init(
        saveDirectory: URL,
        defaultFormat: ImageFormat = .png,
        fileNameTemplate: String = "AIShot {date} at {time}",
        includeCursor: Bool = false,
        freezeBeforeRegionSelect: Bool = true,
        postCaptureAction: PostCaptureAction = .copyToClipboard,
        showNotification: Bool = true,
        captureSoundName: String = "Pop",
        launchAtLogin: Bool = false,
        mcpEnabled: Bool = false,
        mcpPort: Int = 47600,
        mcpRequireConfirmationForInput: Bool = true,
        captureMetadataEnabled: Bool = true,
        applyLastTag: Bool = false,
        lastTag: String? = nil
    ) {
        self.saveDirectory = saveDirectory
        self.defaultFormat = defaultFormat
        self.fileNameTemplate = fileNameTemplate
        self.includeCursor = includeCursor
        self.freezeBeforeRegionSelect = freezeBeforeRegionSelect
        self.postCaptureAction = postCaptureAction
        self.showNotification = showNotification
        self.captureSoundName = captureSoundName
        self.launchAtLogin = launchAtLogin
        self.mcpEnabled = mcpEnabled
        self.mcpPort = mcpPort
        self.mcpRequireConfirmationForInput = mcpRequireConfirmationForInput
        self.captureMetadataEnabled = captureMetadataEnabled
        self.applyLastTag = applyLastTag
        self.lastTag = lastTag
    }

    /// Resilient decoding: unknown/missing keys fall back to defaults so adding
    /// a setting never invalidates a user's stored configuration.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        saveDirectory = try container.decodeIfPresent(URL.self, forKey: .saveDirectory) ?? fallback.saveDirectory
        defaultFormat = try container.decodeIfPresent(ImageFormat.self, forKey: .defaultFormat) ?? fallback.defaultFormat
        fileNameTemplate = try container.decodeIfPresent(String.self, forKey: .fileNameTemplate) ?? fallback.fileNameTemplate
        includeCursor = try container.decodeIfPresent(Bool.self, forKey: .includeCursor) ?? fallback.includeCursor
        freezeBeforeRegionSelect = try container.decodeIfPresent(Bool.self, forKey: .freezeBeforeRegionSelect) ?? fallback.freezeBeforeRegionSelect
        postCaptureAction = try container.decodeIfPresent(PostCaptureAction.self, forKey: .postCaptureAction) ?? fallback.postCaptureAction
        showNotification = try container.decodeIfPresent(Bool.self, forKey: .showNotification) ?? fallback.showNotification
        captureSoundName = try container.decodeIfPresent(String.self, forKey: .captureSoundName) ?? fallback.captureSoundName
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        mcpEnabled = try container.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? fallback.mcpEnabled
        mcpPort = try container.decodeIfPresent(Int.self, forKey: .mcpPort) ?? fallback.mcpPort
        mcpRequireConfirmationForInput = try container.decodeIfPresent(Bool.self, forKey: .mcpRequireConfirmationForInput) ?? fallback.mcpRequireConfirmationForInput
        captureMetadataEnabled = try container.decodeIfPresent(Bool.self, forKey: .captureMetadataEnabled) ?? fallback.captureMetadataEnabled
        applyLastTag = try container.decodeIfPresent(Bool.self, forKey: .applyLastTag) ?? fallback.applyLastTag
        lastTag = try container.decodeIfPresent(String.self, forKey: .lastTag) ?? fallback.lastTag
    }

    /// Sensible defaults: save to `~/Pictures/AIShot`, PNG, copy to clipboard
    /// after capture, notify, and confirm risky MCP actions.
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
