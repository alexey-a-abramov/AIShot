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

/// Where the notes/tags database lives.
public enum MetadataLocation: String, Sendable, Codable, CaseIterable {
    /// A hidden `.aishot-metadata.json` dotfile beside each capture (default).
    case hidden
    /// A visible `aishot-metadata.json` beside each capture.
    case visible
    /// A single shared database in a user-chosen folder (`metadataCustomDirectory`).
    case custom
}

/// Output format for screen recordings.
public enum RecordingFormat: String, Sendable, Codable, CaseIterable {
    /// H.264 `.mp4`.
    case mp4
    /// Animated GIF, transcoded from the recorded video after it stops.
    case gif
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
    /// Where the notes/tags database is stored.
    public var metadataLocation: MetadataLocation
    /// Folder for the shared database when `metadataLocation == .custom`
    /// (`nil` falls back to the app-support folder).
    public var metadataCustomDirectory: URL?
    /// Self-timer: seconds to wait (showing a countdown) before Full Screen,
    /// Window, All Displays, or Region captures actually fire. `0` disables it.
    public var captureDelay: TimeInterval
    /// Output format for screen recordings.
    public var recordingFormat: RecordingFormat

    // MARK: Saving

    /// How captures are filed inside `saveDirectory`.
    public var folderOrganization: FolderOrganization
    /// Granularity of the date subfolder, when the organization uses one.
    public var dateFolderGranularity: DateFolderGranularity
    /// Folder used when organizing by tag and the capture has none.
    public var untaggedFolderName: String
    /// Last directory chosen in a "Save As…" panel, used to seed the next one.
    /// Deliberately never affects where automatic saves go — see
    /// `SaveDestinationResolver`.
    public var lastSaveAsDirectory: URL?
    /// Seed the next "Save As…" panel with `lastSaveAsDirectory`.
    public var rememberLastSaveAsDirectory: Bool
    /// ⌘S in the editor writes back to the file it was opened from, instead of
    /// creating a second timestamped copy.
    public var editorSaveOverwritesOriginal: Bool
    /// Show the inline annotation panel after a region selection.
    public var inlineCapturePanel: Bool

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
        lastTag: String? = nil,
        metadataLocation: MetadataLocation = .hidden,
        metadataCustomDirectory: URL? = nil,
        captureDelay: TimeInterval = 0,
        recordingFormat: RecordingFormat = .mp4,
        folderOrganization: FolderOrganization = .none,
        dateFolderGranularity: DateFolderGranularity = .month,
        untaggedFolderName: String = "Unsorted",
        lastSaveAsDirectory: URL? = nil,
        rememberLastSaveAsDirectory: Bool = true,
        editorSaveOverwritesOriginal: Bool = true,
        inlineCapturePanel: Bool = true
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
        self.metadataLocation = metadataLocation
        self.metadataCustomDirectory = metadataCustomDirectory
        self.captureDelay = captureDelay
        self.recordingFormat = recordingFormat
        self.folderOrganization = folderOrganization
        self.dateFolderGranularity = dateFolderGranularity
        self.untaggedFolderName = untaggedFolderName
        self.lastSaveAsDirectory = lastSaveAsDirectory
        self.rememberLastSaveAsDirectory = rememberLastSaveAsDirectory
        self.editorSaveOverwritesOriginal = editorSaveOverwritesOriginal
        self.inlineCapturePanel = inlineCapturePanel
    }

    /// Resilient decoding: unknown/missing keys fall back to defaults so adding
    /// a setting never invalidates a user's stored configuration.
    ///
    /// Note the `try?` on every enum and URL: `decodeIfPresent` *throws* on an
    /// unrecognised raw value, which would propagate out of
    /// `UserDefaultsSettingsStore.load()` and make `AppModel` fall back to
    /// `.default` — silently resetting every other setting the user had.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        saveDirectory = (try? container.decodeIfPresent(URL.self, forKey: .saveDirectory)) ?? fallback.saveDirectory
        defaultFormat = (try? container.decodeIfPresent(ImageFormat.self, forKey: .defaultFormat)) ?? fallback.defaultFormat
        fileNameTemplate = try container.decodeIfPresent(String.self, forKey: .fileNameTemplate) ?? fallback.fileNameTemplate
        includeCursor = try container.decodeIfPresent(Bool.self, forKey: .includeCursor) ?? fallback.includeCursor
        freezeBeforeRegionSelect = try container.decodeIfPresent(Bool.self, forKey: .freezeBeforeRegionSelect) ?? fallback.freezeBeforeRegionSelect
        postCaptureAction = (try? container.decodeIfPresent(PostCaptureAction.self, forKey: .postCaptureAction)) ?? fallback.postCaptureAction
        showNotification = try container.decodeIfPresent(Bool.self, forKey: .showNotification) ?? fallback.showNotification
        captureSoundName = try container.decodeIfPresent(String.self, forKey: .captureSoundName) ?? fallback.captureSoundName
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        mcpEnabled = try container.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? fallback.mcpEnabled
        mcpPort = try container.decodeIfPresent(Int.self, forKey: .mcpPort) ?? fallback.mcpPort
        mcpRequireConfirmationForInput = try container.decodeIfPresent(Bool.self, forKey: .mcpRequireConfirmationForInput) ?? fallback.mcpRequireConfirmationForInput
        captureMetadataEnabled = try container.decodeIfPresent(Bool.self, forKey: .captureMetadataEnabled) ?? fallback.captureMetadataEnabled
        applyLastTag = try container.decodeIfPresent(Bool.self, forKey: .applyLastTag) ?? fallback.applyLastTag
        lastTag = try container.decodeIfPresent(String.self, forKey: .lastTag) ?? fallback.lastTag
        metadataLocation = (try? container.decodeIfPresent(MetadataLocation.self, forKey: .metadataLocation)) ?? fallback.metadataLocation
        metadataCustomDirectory = (try? container.decodeIfPresent(URL.self, forKey: .metadataCustomDirectory)) ?? fallback.metadataCustomDirectory
        captureDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .captureDelay) ?? fallback.captureDelay
        recordingFormat = (try? container.decodeIfPresent(RecordingFormat.self, forKey: .recordingFormat)) ?? fallback.recordingFormat
        folderOrganization = (try? container.decodeIfPresent(FolderOrganization.self, forKey: .folderOrganization)) ?? fallback.folderOrganization
        dateFolderGranularity = (try? container.decodeIfPresent(DateFolderGranularity.self, forKey: .dateFolderGranularity)) ?? fallback.dateFolderGranularity
        untaggedFolderName = (try? container.decodeIfPresent(String.self, forKey: .untaggedFolderName)) ?? fallback.untaggedFolderName
        lastSaveAsDirectory = (try? container.decodeIfPresent(URL.self, forKey: .lastSaveAsDirectory)) ?? fallback.lastSaveAsDirectory
        rememberLastSaveAsDirectory = (try? container.decodeIfPresent(Bool.self, forKey: .rememberLastSaveAsDirectory)) ?? fallback.rememberLastSaveAsDirectory
        editorSaveOverwritesOriginal = (try? container.decodeIfPresent(Bool.self, forKey: .editorSaveOverwritesOriginal)) ?? fallback.editorSaveOverwritesOriginal
        inlineCapturePanel = (try? container.decodeIfPresent(Bool.self, forKey: .inlineCapturePanel)) ?? fallback.inlineCapturePanel
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
