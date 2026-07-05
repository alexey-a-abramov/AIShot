import Testing
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import AIShotAnnotation

struct RendererTests {
    private func basePNG(_ width: Int, _ height: Int) -> Data {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func dimensions(_ data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image.width, image.height)
    }

    @Test func rendersAnnotationsPreservingSize() async throws {
        let base = basePNG(64, 48)
        let document = AnnotationDocument(
            baseImageSize: CGSize(width: 64, height: 48),
            annotations: [
                Annotation(tool: .arrow, points: [CGPoint(x: 5, y: 5), CGPoint(x: 50, y: 40)], color: .red, lineWidth: 3),
                Annotation(tool: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 25)], color: .yellow, lineWidth: 2),
                Annotation(tool: .blur, points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)]),
                Annotation(tool: .text, points: [CGPoint(x: 4, y: 30)], color: .white, lineWidth: 1, text: "Hi", fontSize: 12),
            ]
        )
        let output = try await CoreImageAnnotationRenderer().render(document, onto: base)
        #expect(output.count > 0)
        #expect(dimensions(output) ?? (0, 0) == (64, 48))
        // Drawing changed pixels, so the bytes differ from the plain base.
        #expect(output != base)
    }

    @Test func emptyDocumentStillReencodes() async throws {
        let base = basePNG(20, 20)
        let output = try await CoreImageAnnotationRenderer()
            .render(AnnotationDocument(baseImageSize: CGSize(width: 20, height: 20)), onto: base)
        #expect(dimensions(output) ?? (0, 0) == (20, 20))
    }

    @Test func undecodableBaseThrows() async {
        await #expect(throws: (any Error).self) {
            _ = try await CoreImageAnnotationRenderer()
                .render(AnnotationDocument(baseImageSize: .zero), onto: Data([0, 1, 2, 3]))
        }
    }

    @Test func counterBadgeDrawsItsNumber() async throws {
        // A counter with a number set must render differently than the same
        // badge with no number — otherwise the digit isn't actually painted.
        let base = basePNG(80, 80)
        let numbered = AnnotationDocument(
            baseImageSize: CGSize(width: 80, height: 80),
            annotations: [Annotation(tool: .counter, points: [CGPoint(x: 40, y: 40)], color: .red, lineWidth: 4, text: "1")]
        )
        let unnumbered = AnnotationDocument(
            baseImageSize: CGSize(width: 80, height: 80),
            annotations: [Annotation(tool: .counter, points: [CGPoint(x: 40, y: 40)], color: .red, lineWidth: 4, text: nil)]
        )
        let numberedOutput = try await CoreImageAnnotationRenderer().render(numbered, onto: base)
        let unnumberedOutput = try await CoreImageAnnotationRenderer().render(unnumbered, onto: base)
        #expect(numberedOutput != unnumberedOutput)
    }
}
