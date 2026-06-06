import CoreGraphics
import Foundation

/// Annotation primitives offered by the editor and the `annotate` MCP tool.
public enum AnnotationTool: String, Sendable, Codable, CaseIterable {
    case arrow
    case line
    case rectangle
    case ellipse
    case text
    case highlighter
    case blur
    case pixelate
    /// Auto-incrementing numbered badge (Flameshot/Snagit "step" style).
    case counter
}

/// A simple, `Codable` RGBA color so annotation documents serialize without
/// depending on AppKit's `NSColor`.
public struct RGBAColor: Sendable, Codable, Equatable {
    public var r, g, b, a: Double
    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let red = RGBAColor(r: 1.0, g: 0.23, b: 0.19)
    public static let yellow = RGBAColor(r: 1.0, g: 0.80, b: 0.0)
    public static let black = RGBAColor(r: 0, g: 0, b: 0)
    public static let white = RGBAColor(r: 1, g: 1, b: 1)

    /// The equivalent sRGB `CGColor` for drawing.
    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// A copy with a different alpha.
    public func withAlpha(_ alpha: Double) -> RGBAColor {
        RGBAColor(r: r, g: g, b: b, a: alpha)
    }
}

/// A single annotation. `points` are interpreted per-tool:
/// arrow/line = `[start, end]`; rectangle/ellipse/blur/pixelate = `[corner,
/// oppositeCorner]`; text/counter = `[origin]`.
public struct Annotation: Sendable, Identifiable, Codable, Equatable {
    public var id: UUID
    public var tool: AnnotationTool
    public var points: [CGPoint]
    public var color: RGBAColor
    public var lineWidth: Double
    public var text: String?
    public var fontSize: Double?

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        points: [CGPoint],
        color: RGBAColor = .red,
        lineWidth: Double = 3,
        text: String? = nil,
        fontSize: Double? = nil
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
    }

    /// Axis-aligned bounding box covering the geometry, padded by the stroke.
    public var boundingBox: CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(origin: first, size: .zero)
        for p in points.dropFirst() {
            rect = rect.union(CGRect(origin: p, size: .zero))
        }
        return rect.insetBy(dx: -lineWidth, dy: -lineWidth)
    }
}

/// An ordered set of annotations over a base image of a known size.
public struct AnnotationDocument: Sendable, Codable, Equatable {
    public var baseImageSize: CGSize
    public var annotations: [Annotation]

    public init(baseImageSize: CGSize, annotations: [Annotation] = []) {
        self.baseImageSize = baseImageSize
        self.annotations = annotations
    }
}
