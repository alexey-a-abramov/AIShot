import Testing
import CoreGraphics
@testable import AIShotShared

struct GeometryTests {
    @Test func clampKeepsRectInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let clamped = Geometry.clamp(CGRect(x: -10, y: 50, width: 200, height: 80), to: bounds)
        #expect(clamped.minX == 0)
        #expect(clamped.maxX <= 100)
        #expect(clamped.maxY <= 100)
    }

    @Test func scaledMultipliesEveryComponent() {
        let scaled = Geometry.scaled(CGRect(x: 1, y: 2, width: 3, height: 4), by: 2)
        #expect(scaled == CGRect(x: 2, y: 4, width: 6, height: 8))
    }

    @Test func unionIgnoresNullRect() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(Geometry.union(.null, rect) == rect)
        #expect(Geometry.union(rect, .null) == rect)
    }

    @Test func flipToTopLeftInvertsY() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let flipped = Geometry.flipToTopLeft(CGPoint(x: 100, y: 600), in: screen)
        #expect(flipped == CGPoint(x: 100, y: 200))
    }
}
