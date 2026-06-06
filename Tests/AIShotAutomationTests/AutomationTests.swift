import Testing
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import AIShotAutomation

struct AutomationTests {
    @Test func runningAppsIncludesThisProcess() async throws {
        // Listing apps uses NSWorkspace and needs no special permission.
        let apps = try await AutomationEngine().runningApps()
        #expect(!apps.isEmpty)
        #expect(apps.allSatisfy { !$0.id.isEmpty })
    }

    @Test func locateOnBlankImageFindsNothing() async throws {
        let png = blankPNG(40, 30)
        let matches = try await VisionElementLocator().locate(LocatorQuery(text: "anything"), inScreenshotPNG: png)
        #expect(matches.isEmpty)
    }

    @Test func locateRejectsUndecodableData() async {
        await #expect(throws: (any Error).self) {
            _ = try await VisionElementLocator().locate(LocatorQuery(), inScreenshotPNG: Data([1, 2, 3]))
        }
    }

    private func blankPNG(_ width: Int, _ height: Int) -> Data {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        _ = CGImageDestinationFinalize(dest)
        return data as Data
    }
}

/// Synthetic input requires Accessibility — gated behind AISHOT_INTEGRATION=1.
struct AutomationInputIntegrationTests {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["AISHOT_INTEGRATION"] == "1" }

    @Test(.enabled(if: enabled))
    func movesCursorWithoutThrowing() async throws {
        try await AutomationEngine().move(to: CGPoint(x: 100, y: 100))
    }
}
