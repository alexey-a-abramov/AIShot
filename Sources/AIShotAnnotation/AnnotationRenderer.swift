import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AIShotCore

/// Pure arrowhead math, shared by the live editor and the flattening renderer.
public enum ArrowGeometry {
    /// The two barb endpoints for an arrowhead whose tip is at `tip`, arriving
    /// from `from`.
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

/// Core Graphics + Core Image renderer.
///
/// Annotation points are interpreted in the base image's pixel space with a
/// top-left origin. Drawing happens in three passes over an upright base:
/// redaction (blur/pixelate), vector shapes, then text — so text/shapes sit
/// above blurred regions.
public actor CoreImageAnnotationRenderer: AnnotationRendering {
    public init() {}

    public func render(_ document: AnnotationDocument, onto basePNG: Data) async throws -> Data {
        guard let source = CGImageSourceCreateWithData(basePNG as CFData, nil),
              let base = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIShotError.encodingFailed("annotation: undecodable base image")
        }
        let width = base.width
        let height = base.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AIShotError.encodingFailed("annotation: context allocation failed")
        }

        let h = CGFloat(height)
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))

        let ciContext = CIContext()
        for annotation in document.annotations where annotation.tool == .blur || annotation.tool == .pixelate {
            applyRedaction(annotation, base: base, ctx: ctx, ciContext: ciContext)
        }

        // Vector shapes in a top-left coordinate frame.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: h)
        ctx.scaleBy(x: 1, y: -1)
        for annotation in document.annotations {
            drawShape(annotation, in: ctx)
        }
        ctx.restoreGState()

        // Text in the bottom-left frame (manual y conversion).
        for annotation in document.annotations where annotation.tool == .text || annotation.tool == .counter {
            drawText(annotation, in: ctx, imageHeight: h)
        }

        guard let out = ctx.makeImage() else {
            throw AIShotError.encodingFailed("annotation: makeImage failed")
        }
        return try Self.encodePNG(out)
    }

    // MARK: - Shapes

    private func drawShape(_ annotation: Annotation, in ctx: CGContext) {
        let color = annotation.color.cgColor
        ctx.setStrokeColor(color)
        ctx.setLineWidth(CGFloat(annotation.lineWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch annotation.tool {
        case .line:
            guard annotation.points.count >= 2 else { return }
            ctx.beginPath()
            ctx.move(to: annotation.points[0])
            ctx.addLine(to: annotation.points[1])
            ctx.strokePath()
        case .arrow:
            guard annotation.points.count >= 2 else { return }
            let from = annotation.points[0]
            let tip = annotation.points[1]
            let head = ArrowGeometry.arrowHead(from: from, tip: tip, length: max(12, CGFloat(annotation.lineWidth) * 4.5))
            // Shaft.
            ctx.beginPath()
            ctx.move(to: from)
            ctx.addLine(to: tip)
            ctx.strokePath()
            // Filled triangular head.
            ctx.beginPath()
            ctx.move(to: tip)
            ctx.addLine(to: head.left)
            ctx.addLine(to: head.right)
            ctx.closePath()
            ctx.setFillColor(color)
            ctx.fillPath()
        case .rectangle:
            ctx.stroke(Self.rect(from: annotation.points))
        case .ellipse:
            ctx.strokeEllipse(in: Self.rect(from: annotation.points))
        case .highlighter:
            ctx.setFillColor(annotation.color.withAlpha(0.3).cgColor)
            ctx.fill(Self.rect(from: annotation.points))
        case .counter:
            let center = annotation.points.first ?? .zero
            let radius = max(12, CGFloat(annotation.lineWidth) * 5)
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        case .text, .blur, .pixelate:
            break // handled in other passes
        }
    }

    // MARK: - Redaction

    private func applyRedaction(_ annotation: Annotation, base: CGImage, ctx: CGContext, ciContext: CIContext) {
        guard annotation.points.count >= 2 else { return }
        let rectTL = Self.rect(from: annotation.points)
        let input = CIImage(cgImage: base).clampedToExtent()
        let filter: CIFilter? = annotation.tool == .blur
            ? CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input, kCIInputRadiusKey: 14])
            : CIFilter(name: "CIPixellate", parameters: [kCIInputImageKey: input, kCIInputScaleKey: 16])
        guard let output = filter?.outputImage else { return }

        // Convert the top-left rect into CoreImage's bottom-left space.
        let ciRect = CGRect(
            x: rectTL.minX,
            y: CGFloat(base.height) - rectTL.maxY,
            width: rectTL.width,
            height: rectTL.height
        )
        guard let cropped = ciContext.createCGImage(output, from: ciRect) else { return }
        ctx.draw(cropped, in: ciRect)
    }

    // MARK: - Text

    private func drawText(_ annotation: Annotation, in ctx: CGContext, imageHeight: CGFloat) {
        guard let text = annotation.text, !text.isEmpty, let point = annotation.points.first else { return }
        let fontSize = CGFloat(annotation.fontSize ?? 18)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: annotation.color.cgColor,
        ] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: point.x, y: imageHeight - point.y - fontSize)
        CTLineDraw(line, ctx)
    }

    // MARK: - Helpers

    private static func rect(from points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw AIShotError.encodingFailed("annotation: PNG destination failed")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AIShotError.encodingFailed("annotation: PNG finalize failed")
        }
        return data as Data
    }
}
