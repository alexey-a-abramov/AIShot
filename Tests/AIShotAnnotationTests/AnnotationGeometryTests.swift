import Testing
import CoreGraphics
import Foundation
@testable import AIShotAnnotation

struct AnnotationGeometryTests {
    @Test func boundingBoxCoversAllPoints() {
        let annotation = Annotation(
            tool: .arrow,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 20)],
            lineWidth: 2
        )
        let box = annotation.boundingBox
        #expect(box.minX <= 0)
        #expect(box.maxX >= 10)
        #expect(box.maxY >= 20)
    }

    @Test func emptyPointsYieldNullBox() {
        let annotation = Annotation(tool: .text, points: [], text: "hi")
        #expect(annotation.boundingBox.isNull)
    }

    @Test func arrowHeadIsSymmetricForHorizontalArrow() {
        let head = ArrowGeometry.arrowHead(from: CGPoint(x: 0, y: 0), tip: CGPoint(x: 100, y: 0))
        // Barbs mirror across the arrow's axis, and sit behind the tip.
        #expect(abs(head.left.y + head.right.y) < 0.0001)
        #expect(abs(head.left.x - head.right.x) < 0.0001)
        #expect(head.left.x < 100)
    }

    @Test func documentRoundTripsThroughJSON() throws {
        let document = AnnotationDocument(
            baseImageSize: CGSize(width: 800, height: 600),
            annotations: [Annotation(tool: .rectangle, points: [.zero, CGPoint(x: 5, y: 5)])]
        )
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: data)
        #expect(decoded == document)
    }

    @Test func contrastingLabelColorPicksWhiteOnDarkSaturatedFills() {
        // Red and black badges need white numbers to stay legible.
        #expect(RGBAColor.red.contrastingLabelColor == .white)
        #expect(RGBAColor.black.contrastingLabelColor == .white)
    }

    @Test func contrastingLabelColorPicksBlackOnLightFills() {
        // Yellow and white badges need black numbers to stay legible.
        #expect(RGBAColor.yellow.contrastingLabelColor == .black)
        #expect(RGBAColor.white.contrastingLabelColor == .black)
    }
}
