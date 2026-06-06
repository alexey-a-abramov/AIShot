import CoreGraphics

/// Pure geometry helpers used by capture cropping, overlay selection, and
/// annotation hit-testing. Kept dependency-free so they're trivially testable.
public enum Geometry {
    /// Returns `rect` clamped so it never extends outside `bounds`.
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let x = min(max(rect.minX, bounds.minX), bounds.maxX)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY)
        let maxX = min(rect.maxX, bounds.maxX)
        let maxY = min(rect.maxY, bounds.maxY)
        return CGRect(x: x, y: y, width: max(0, maxX - x), height: max(0, maxY - y))
    }

    /// The smallest rectangle containing both inputs, ignoring null rects.
    public static func union(_ a: CGRect, _ b: CGRect) -> CGRect {
        if a.isNull { return b }
        if b.isNull { return a }
        return a.union(b)
    }

    /// Scales every component of `rect` by `factor` — used to convert between
    /// point space and pixel (backing-store) space on Retina displays.
    public static func scaled(_ rect: CGRect, by factor: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * factor,
            y: rect.minY * factor,
            width: rect.width * factor,
            height: rect.height * factor
        )
    }

    /// Converts a point from AppKit's bottom-left, global coordinate space to
    /// the top-left, per-screen space used by Quartz / ScreenCaptureKit.
    ///
    /// - Parameters:
    ///   - point: A point in AppKit global coordinates.
    ///   - screenFrame: The target screen's frame in the same global space.
    public static func flipToTopLeft(_ point: CGPoint, in screenFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX,
                y: screenFrame.maxY - point.y)
    }
}
