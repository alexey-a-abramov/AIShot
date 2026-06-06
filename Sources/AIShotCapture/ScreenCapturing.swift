import CoreGraphics
import Foundation
import AIShotCore
import AIShotShared

/// Raw capture output, before persistence. Carries already-encoded bytes plus
/// metadata, so it crosses actor boundaries safely (no `CGImage`).
public struct CapturedImage: Sendable, Equatable {
    public var pixelSize: CGSize
    public var scale: CGFloat
    public var format: ImageFormat
    public var data: Data

    public init(pixelSize: CGSize, scale: CGFloat, format: ImageFormat, data: Data) {
        self.pixelSize = pixelSize
        self.scale = scale
        self.format = format
        self.data = data
    }
}

/// Abstraction over the capture backend so the MCP service, hotkeys, and UI all
/// share one entry point — and so tests can inject a fake.
///
/// Coordinate convention: for `.region`, `CaptureRequest.rect` is in
/// **display-local, top-left** points (the overlay/app converts global AppKit
/// coordinates before calling; see `Geometry.flipToTopLeft`).
public protocol ScreenCapturing: Sendable {
    /// All connected displays.
    func availableDisplays() async throws -> [DisplayInfo]
    /// On-screen windows, excluding AIShot's own windows.
    func availableWindows() async throws -> [WindowInfo]
    /// Performs a capture and returns the encoded image.
    func capture(_ request: CaptureRequest) async throws -> CapturedImage
}
