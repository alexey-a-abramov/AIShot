import Testing
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import AIShotAnnotation

struct BeautifierTests {
    private func basePNG(_ width: Int, _ height: Int) -> Data {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        _ = CGImageDestinationFinalize(dest)
        return data as Data
    }

    private func dimensions(_ data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image.width, image.height)
    }

    @Test func beautifyAddsPaddingOnBothSides() throws {
        let output = try Beautifier.beautify(basePNG(40, 30), options: BeautifyOptions(padding: 20))
        #expect(dimensions(output) ?? (0, 0) == (80, 70))
    }

    @Test func beautifyRejectsUndecodable() {
        #expect(throws: (any Error).self) {
            _ = try Beautifier.beautify(Data([1, 2, 3]))
        }
    }
}
