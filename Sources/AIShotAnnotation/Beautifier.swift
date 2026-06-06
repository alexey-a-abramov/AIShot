import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AIShotCore

/// Options for "beautifying" a screenshot (Xnapper-style framing).
public struct BeautifyOptions: Sendable {
    public var padding: CGFloat
    public var cornerRadius: CGFloat
    public var shadowRadius: CGFloat
    public var backgroundTop: RGBAColor
    public var backgroundBottom: RGBAColor

    public init(
        padding: CGFloat = 64,
        cornerRadius: CGFloat = 16,
        shadowRadius: CGFloat = 28,
        backgroundTop: RGBAColor = RGBAColor(r: 0.36, g: 0.42, b: 0.95),
        backgroundBottom: RGBAColor = RGBAColor(r: 0.62, g: 0.35, b: 0.91)
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.backgroundTop = backgroundTop
        self.backgroundBottom = backgroundBottom
    }

    public static let `default` = BeautifyOptions()
}

/// Renders a screenshot onto a gradient background with padding, rounded
/// corners, and a drop shadow.
public enum Beautifier {
    public static func beautify(_ png: Data, options: BeautifyOptions = .default) throws -> Data {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let base = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIShotError.invalidRequest("beautify: undecodable image")
        }
        let baseWidth = CGFloat(base.width)
        let baseHeight = CGFloat(base.height)
        let outWidth = Int(baseWidth + options.padding * 2)
        let outHeight = Int(baseHeight + options.padding * 2)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AIShotError.encodingFailed("beautify: context allocation failed")
        }

        // Vertical gradient background.
        let colors = [options.backgroundTop.cgColor, options.backgroundBottom.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: CGFloat(outHeight)),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }

        let imageRect = CGRect(x: options.padding, y: options.padding, width: baseWidth, height: baseHeight)
        let rounded = CGPath(roundedRect: imageRect, cornerWidth: options.cornerRadius, cornerHeight: options.cornerRadius, transform: nil)

        // Drop shadow cast by a filled rounded rect.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -options.shadowRadius / 3), blur: options.shadowRadius,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.addPath(rounded)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        // Clipped image.
        ctx.saveGState()
        ctx.addPath(rounded)
        ctx.clip()
        ctx.draw(base, in: imageRect)
        ctx.restoreGState()

        guard let out = ctx.makeImage() else {
            throw AIShotError.encodingFailed("beautify: makeImage failed")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw AIShotError.encodingFailed("beautify: PNG destination failed")
        }
        CGImageDestinationAddImage(destination, out, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AIShotError.encodingFailed("beautify: PNG finalize failed")
        }
        return data as Data
    }
}
