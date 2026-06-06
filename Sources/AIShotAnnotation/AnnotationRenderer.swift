import CoreGraphics
import Foundation
import AIShotCore

/// Pure arrowhead math, shared by the live editor and the flattening renderer.
public enum ArrowGeometry {
    /// The two barb endpoints for an arrowhead whose tip is at `tip`, arriving
    /// from `from`.
    /// - Parameters:
    ///   - length: Barb length in points.
    ///   - angle: Half-angle of the arrowhead in radians.
    public static func arrowHead(
        from: CGPoint,
        tip: CGPoint,
        length: CGFloat = 16,
        angle: CGFloat = .pi / 7
    ) -> (left: CGPoint, right: CGPoint) {
        let theta = atan2(Double(tip.y - from.y), Double(tip.x - from.x))
        let a = Double(angle)
        let len = Double(length)
        let left = CGPoint(
            x: Double(tip.x) - len * cos(theta - a),
            y: Double(tip.y) - len * sin(theta - a)
        )
        let right = CGPoint(
            x: Double(tip.x) - len * cos(theta + a),
            y: Double(tip.y) - len * sin(theta + a)
        )
        return (left, right)
    }
}

/// Flattens an `AnnotationDocument` onto a base image, producing new PNG bytes.
public protocol AnnotationRendering: Sendable {
    func render(_ document: AnnotationDocument, onto basePNG: Data) async throws -> Data
}

/// Core Image / Core Graphics renderer.
///
/// Phase P1c draws strokes/text via `CGContext` and applies `CIFilter`
/// gaussian-blur / pixellate for the `blur`/`pixelate` (redaction) tools.
public actor CoreImageAnnotationRenderer: AnnotationRendering {
    public init() {}

    public func render(_ document: AnnotationDocument, onto basePNG: Data) async throws -> Data {
        throw AIShotError.notImplemented("CoreImageAnnotationRenderer.render (P1c)")
    }
}
