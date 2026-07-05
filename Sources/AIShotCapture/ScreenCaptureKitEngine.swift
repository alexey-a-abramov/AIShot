import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit
import AIShotCore
import AIShotShared

/// ScreenCaptureKit-backed capture engine.
///
/// Enumerates via `SCShareableContent`, captures stills via
/// `SCScreenshotManager.captureImage(contentFilter:configuration:)`, and
/// multiplies the configuration size by the display's pixel scale for
/// Retina-correct output.
///
/// Nothing is excluded from region/display/all-displays captures — including
/// AIShot's own menu, Dashboard, Settings, and editor windows, so those are
/// capturable like any other app's UI. The selection overlay and self-timer
/// countdown are synchronously torn down before this actually runs (see
/// `SelectionOverlayController.finish` / `CaptureCountdownController.run`),
/// and `AppModel.dismissEphemeralCaptureUI()` proactively hides the
/// post-capture HUD and note/tag prompt at the start of every new capture —
/// so a rapid second capture can't show leftover chrome from the first.
public actor ScreenCaptureKitEngine: ScreenCapturing {
    private let logger = Logger.aishot("capture")

    public init() {}

    public func availableDisplays() async throws -> [DisplayInfo] {
        let content = try await shareableContent()
        let main = CGMainDisplayID()
        return content.displays.map { display in
            DisplayInfo(
                id: display.displayID,
                name: "Display \(display.displayID)",
                frame: display.frame,
                scale: Self.displayScale(display.displayID),
                isMain: display.displayID == main
            )
        }
    }

    public func availableWindows() async throws -> [WindowInfo] {
        let content = try await shareableContent()
        let own = ownBundleID
        return content.windows.compactMap { window -> WindowInfo? in
            guard let app = window.owningApplication else { return nil }
            if app.bundleIdentifier == own { return nil }
            return WindowInfo(
                id: window.windowID,
                title: window.title ?? "",
                appName: app.applicationName,
                bundleID: app.bundleIdentifier,
                frame: window.frame,
                isOnScreen: window.isOnScreen
            )
        }
    }

    public func capture(_ request: CaptureRequest) async throws -> CapturedImage {
        if request.delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(request.delay * 1_000_000_000))
        }
        let content = try await shareableContent()
        switch request.mode {
        case .region, .display:
            return try await captureDisplay(request, content: content)
        case .window:
            return try await captureWindow(request, content: content)
        case .allDisplays:
            return try await captureAllDisplays(request, content: content)
        }
    }

    // MARK: - Capture modes

    private func captureDisplay(_ request: CaptureRequest, content: SCShareableContent) async throws -> CapturedImage {
        let targetID = request.displayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == targetID }) else {
            throw AIShotError.targetNotFound("display \(targetID)")
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.showsCursor = request.includeCursor
        config.captureResolution = .best

        let regionPoints: CGRect
        if request.mode == .region, let rect = request.rect {
            config.sourceRect = rect
            regionPoints = rect
        } else {
            regionPoints = filter.contentRect
        }
        config.width = Int((regionPoints.width * scale).rounded())
        config.height = Int((regionPoints.height * scale).rounded())

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try Self.makeResult(image, scale: scale, format: request.format)
    }

    private func captureWindow(_ request: CaptureRequest, content: SCShareableContent) async throws -> CapturedImage {
        guard let id = request.windowID,
              let window = content.windows.first(where: { $0.windowID == id }) else {
            throw AIShotError.targetNotFound("window \(request.windowID.map(String.init) ?? "nil")")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.showsCursor = request.includeCursor
        config.ignoreShadowsSingleWindow = !request.includeWindowShadow
        config.captureResolution = .best
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try Self.makeResult(image, scale: scale, format: request.format)
    }

    private func captureAllDisplays(_ request: CaptureRequest, content: SCShareableContent) async throws -> CapturedImage {
        var shots: [(frame: CGRect, image: CGImage, scale: CGFloat)] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            let config = SCStreamConfiguration()
            config.showsCursor = request.includeCursor
            config.captureResolution = .best
            config.width = Int((filter.contentRect.width * scale).rounded())
            config.height = Int((filter.contentRect.height * scale).rounded())
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            shots.append((display.frame, image, scale))
        }
        let composed = try Self.composite(shots)
        return try Self.makeResult(composed.image, scale: composed.scale, format: request.format)
    }

    // MARK: - Helpers

    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? AIShot.bundleID }

    private func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            logger.error("SCShareableContent failed: \(error.localizedDescription, privacy: .public)")
            throw AIShotError.permissionDenied(.screenRecording)
        }
    }

    private static func makeResult(_ image: CGImage, scale: CGFloat, format: ImageFormat) throws -> CapturedImage {
        let data = try ImageCodec.encode(image, as: format)
        return CapturedImage(
            pixelSize: CGSize(width: image.width, height: image.height),
            scale: scale,
            format: format,
            data: data
        )
    }

    private static func displayScale(_ id: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }

    /// Composites per-display captures into one image using global frames
    /// (top-left origin), drawing into a bottom-left CG context.
    private static func composite(_ shots: [(frame: CGRect, image: CGImage, scale: CGFloat)]) throws -> (image: CGImage, scale: CGFloat) {
        guard let first = shots.first else { throw AIShotError.captureFailed("no displays") }
        let scale = shots.map(\.scale).max() ?? 1
        let unionPoints = shots.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let pxW = Int((unionPoints.width * scale).rounded())
        let pxH = Int((unionPoints.height * scale).rounded())
        guard pxW > 0, pxH > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AIShotError.captureFailed("could not allocate composite context")
        }
        for shot in shots {
            let xPx = (shot.frame.minX - unionPoints.minX) * scale
            let topPx = (shot.frame.minY - unionPoints.minY) * scale
            let hPx = CGFloat(shot.image.height)
            let yPx = CGFloat(pxH) - topPx - hPx
            ctx.draw(shot.image, in: CGRect(x: xPx, y: yPx, width: CGFloat(shot.image.width), height: hPx))
        }
        guard let out = ctx.makeImage() else { throw AIShotError.captureFailed("composite makeImage failed") }
        return (out, scale)
    }
}
