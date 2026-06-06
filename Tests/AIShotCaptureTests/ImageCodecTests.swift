import Testing
import CoreGraphics
import Foundation
@testable import AIShotCapture
@testable import AIShotCore

struct ImageCodecTests {
    /// Builds a solid-color test image without any screen/permission access.
    private func makeImage(_ width: Int, _ height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    @Test func pngRoundTripPreservesDimensions() throws {
        let image = makeImage(8, 6)
        let data = try ImageCodec.encode(image, as: .png)
        #expect(data.count > 0)
        // PNG signature.
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        let decoded = try ImageCodec.decode(data)
        #expect(decoded.width == 8)
        #expect(decoded.height == 6)
    }

    @Test func jpegEncodesWithMarker() throws {
        let data = try ImageCodec.encode(makeImage(4, 4), as: .jpeg, quality: 0.8)
        #expect(data.count > 0)
        // JPEG SOI marker.
        #expect(Array(data.prefix(2)) == [0xFF, 0xD8])
    }

    @Test func everyFormatEncodes() throws {
        let image = makeImage(4, 4)
        for format in ImageFormat.allCases {
            let data = try ImageCodec.encode(image, as: format)
            #expect(data.count > 0, "format \(format.rawValue) produced no data")
        }
    }

    @Test func stitchVerticalTrimsOverlap() throws {
        let a = try ImageCodec.encode(makeImage(20, 30), as: .png)
        let b = try ImageCodec.encode(makeImage(20, 30), as: .png)
        let stitched = try ImageStitcher.stitchVertical([a, b], overlap: 10)
        let decoded = try ImageCodec.decode(stitched)
        #expect(decoded.width == 20)
        #expect(decoded.height == 50) // 30 + (30 - 10)
    }
}

/// Live capture — requires Screen Recording. Skipped unless AISHOT_INTEGRATION=1.
struct ScreenCaptureIntegrationTests {
    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["AISHOT_INTEGRATION"] == "1"
    }

    @Test(.enabled(if: enabled))
    func enumeratesAndCapturesMainDisplay() async throws {
        let engine = ScreenCaptureKitEngine()
        let displays = try await engine.availableDisplays()
        #expect(!displays.isEmpty)
        let main = displays.first(where: \.isMain) ?? displays[0]
        let shot = try await engine.capture(CaptureRequest(mode: .display, displayID: main.id))
        #expect(shot.pixelSize.width > 0)
        #expect(shot.data.count > 0)
    }
}
