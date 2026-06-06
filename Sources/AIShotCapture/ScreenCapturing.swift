import CoreGraphics
import Foundation
import AIShotCore
import AIShotShared

/// Raw capture output, before persistence. Deliberately platform-light (just
/// PNG bytes + metadata) so callers and tests don't depend on AppKit/CGImage.
public struct CapturedImage: Sendable, Equatable {
    public var pixelSize: CGSize
    public var scale: CGFloat
    public var pngData: Data

    public init(pixelSize: CGSize, scale: CGFloat, pngData: Data) {
        self.pixelSize = pixelSize
        self.scale = scale
        self.pngData = pngData
    }
}

/// Abstraction over the capture backend so the MCP service, hotkeys, and UI all
/// share one entry point — and so tests can inject a fake.
public protocol ScreenCapturing: Sendable {
    /// All connected displays.
    func availableDisplays() async throws -> [DisplayInfo]
    /// On-screen windows, excluding AIShot's own overlay windows.
    func availableWindows() async throws -> [WindowInfo]
    /// Performs a capture and returns the raw image.
    func capture(_ request: CaptureRequest) async throws -> CapturedImage
}

/// ScreenCaptureKit-backed implementation.
///
/// Phase P1a wires this to `SCShareableContent` (enumeration) and
/// `SCScreenshotManager.captureImage(contentFilter:configuration:)` (still
/// capture), excluding our overlay via `SCContentFilter`, and multiplying the
/// configuration size by the display's `backingScaleFactor` for Retina output.
public actor ScreenCaptureKitEngine: ScreenCapturing {
    public init() {}

    public func availableDisplays() async throws -> [DisplayInfo] {
        throw AIShotError.notImplemented("ScreenCaptureKitEngine.availableDisplays (P1a)")
    }

    public func availableWindows() async throws -> [WindowInfo] {
        throw AIShotError.notImplemented("ScreenCaptureKitEngine.availableWindows (P1a)")
    }

    public func capture(_ request: CaptureRequest) async throws -> CapturedImage {
        throw AIShotError.notImplemented("ScreenCaptureKitEngine.capture (P1a)")
    }
}
