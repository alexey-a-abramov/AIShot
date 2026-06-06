import CoreGraphics
import Foundation
import AIShotCore

/// Vertically stitches a sequence of images (e.g. scrolling-capture frames),
/// trimming a fixed `overlap` of duplicated rows between consecutive frames.
public enum ImageStitcher {
    public static func stitchVertical(_ pngs: [Data], overlap: Int = 0) throws -> Data {
        let images = try pngs.map { try ImageCodec.decode($0) }
        guard let first = images.first else {
            throw AIShotError.invalidRequest("stitch: no images")
        }
        let width = first.width
        let clampedOverlap = max(0, overlap)

        let totalHeight = images.enumerated().reduce(0) { running, pair in
            running + (pair.offset == 0 ? pair.element.height : max(0, pair.element.height - clampedOverlap))
        }
        guard width > 0, totalHeight > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: width, height: totalHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AIShotError.captureFailed("stitch: context allocation failed")
        }

        var yTop = 0
        for (index, image) in images.enumerated() {
            let cropTop = index == 0 ? 0 : min(clampedOverlap, image.height)
            let drawHeight = image.height - cropTop
            guard drawHeight > 0 else { continue }
            let piece = cropTop == 0
                ? image
                : (image.cropping(to: CGRect(x: 0, y: cropTop, width: image.width, height: drawHeight)) ?? image)
            // Place top-to-bottom in a bottom-left context.
            let ctxY = totalHeight - yTop - drawHeight
            ctx.draw(piece, in: CGRect(x: 0, y: ctxY, width: width, height: drawHeight))
            yTop += drawHeight
        }

        guard let out = ctx.makeImage() else {
            throw AIShotError.captureFailed("stitch: makeImage failed")
        }
        return try ImageCodec.encode(out, as: .png)
    }
}
