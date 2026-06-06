import CoreGraphics
import Foundation
import AIShotShared

/// What to capture.
public enum CaptureMode: String, Sendable, Codable, CaseIterable {
    /// A user- or agent-specified rectangle on a display.
    case region
    /// A single window, captured even if partially occluded.
    case window
    /// One full display.
    case display
    /// Every display, stitched into one image.
    case allDisplays
}

/// Output encoding for a captured image.
public enum ImageFormat: String, Sendable, Codable, CaseIterable {
    case png
    case jpeg
    case heic
    case tiff

    /// File extension (without the dot).
    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .tiff: "tiff"
        }
    }

    /// Uniform Type Identifier used by ImageIO / `UTType`.
    public var utTypeIdentifier: String {
        switch self {
        case .png: "public.png"
        case .jpeg: "public.jpeg"
        case .heic: "public.heic"
        case .tiff: "public.tiff"
        }
    }
}

/// A fully specified capture instruction. The same type is produced by the UI,
/// the global hotkeys, and MCP tool calls — one path into the capture engine.
public struct CaptureRequest: Sendable, Codable, Equatable {
    public var mode: CaptureMode
    /// `CGDirectDisplayID` of the target display (for `.display` / `.region`).
    public var displayID: UInt32?
    /// `CGWindowID` of the target window (for `.window`).
    public var windowID: UInt32?
    /// Region in display-space points (for `.region`).
    public var rect: CGRect?
    /// Whether to render the mouse cursor into the capture.
    public var includeCursor: Bool
    /// Whether to include the window's drop shadow (for `.window`).
    public var includeWindowShadow: Bool
    public var format: ImageFormat
    /// Self-timer delay in seconds before the capture fires.
    public var delay: TimeInterval

    public init(
        mode: CaptureMode,
        displayID: UInt32? = nil,
        windowID: UInt32? = nil,
        rect: CGRect? = nil,
        includeCursor: Bool = false,
        includeWindowShadow: Bool = true,
        format: ImageFormat = .png,
        delay: TimeInterval = 0
    ) {
        self.mode = mode
        self.displayID = displayID
        self.windowID = windowID
        self.rect = rect
        self.includeCursor = includeCursor
        self.includeWindowShadow = includeWindowShadow
        self.format = format
        self.delay = delay
    }
}

/// The outcome of a capture, after optional save-to-disk.
public struct CaptureResult: Sendable, Equatable {
    public var id: UUID
    /// Where the image was written, if persistence was requested.
    public var fileURL: URL?
    /// Image size in pixels (already multiplied by `scale`).
    public var pixelSize: CGSize
    /// Backing scale factor of the source display (e.g. 2.0 on Retina).
    public var scale: CGFloat
    public var mode: CaptureMode
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL? = nil,
        pixelSize: CGSize,
        scale: CGFloat,
        mode: CaptureMode,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.pixelSize = pixelSize
        self.scale = scale
        self.mode = mode
        self.createdAt = createdAt
    }
}

/// Describes a connected display for enumeration / targeting.
public struct DisplayInfo: Sendable, Identifiable, Codable, Equatable {
    /// `CGDirectDisplayID`.
    public var id: UInt32
    public var name: String
    /// Frame in global point coordinates.
    public var frame: CGRect
    /// Backing scale factor.
    public var scale: CGFloat
    public var isMain: Bool

    public init(id: UInt32, name: String, frame: CGRect, scale: CGFloat, isMain: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.scale = scale
        self.isMain = isMain
    }
}

/// Describes an on-screen window for enumeration / targeting.
public struct WindowInfo: Sendable, Identifiable, Codable, Equatable {
    /// `CGWindowID`.
    public var id: UInt32
    public var title: String
    public var appName: String
    public var bundleID: String?
    /// Frame in global point coordinates.
    public var frame: CGRect
    public var isOnScreen: Bool

    public init(
        id: UInt32,
        title: String,
        appName: String,
        bundleID: String? = nil,
        frame: CGRect,
        isOnScreen: Bool
    ) {
        self.id = id
        self.title = title
        self.appName = appName
        self.bundleID = bundleID
        self.frame = frame
        self.isOnScreen = isOnScreen
    }
}

/// Errors surfaced by the engines. `notImplemented` marks scaffolded paths.
public enum AIShotError: Error, Sendable, Equatable {
    case notImplemented(String)
    case permissionDenied(Permission)
    case captureFailed(String)
    case invalidRequest(String)
    case targetNotFound(String)
    case encodingFailed(String)
}
