import Testing
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import AIShotService

struct AutoRedactorTests {
    @Test func isSensitiveDetectsCommonPatterns() {
        #expect(AutoRedactor.isSensitive("reach me at a.b+x@example.co.uk"))
        #expect(AutoRedactor.isSensitive("card 4111 1111 1111 1111"))
        #expect(AutoRedactor.isSensitive("host 192.168.0.1"))
        #expect(!AutoRedactor.isSensitive("nothing secret here"))
    }

    @Test func redactBlankImageReturnsOriginal() async throws {
        let png = blankPNG(32, 24)
        let output = try await AutoRedactor().redact(in: png)
        #expect(output == png)
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
