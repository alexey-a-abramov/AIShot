import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AIShotCore

/// Encodes/decodes `CGImage`s using ImageIO, honoring `ImageFormat`.
public enum ImageCodec {
    /// Encodes a `CGImage` to bytes in the requested format.
    /// - Parameter quality: lossy quality (0...1) for JPEG/HEIC; ignored otherwise.
    public static func encode(_ image: CGImage, as format: ImageFormat, quality: CGFloat = 0.9) throws -> Data {
        let data = NSMutableData()
        let type = UTType(format.utTypeIdentifier) ?? .png
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, type.identifier as CFString, 1, nil
        ) else {
            throw AIShotError.encodingFailed("could not create destination for \(format.rawValue)")
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AIShotError.encodingFailed("finalize failed for \(format.rawValue)")
        }
        return data as Data
    }

    /// Decodes image bytes (any ImageIO-supported format) into a `CGImage`.
    public static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIShotError.encodingFailed("could not decode image data")
        }
        return image
    }

    /// Decodes a downsampled thumbnail from a file **without** ever allocating
    /// the full-resolution bitmap — essential for grids of large screenshots.
    ///
    /// - Parameter maxPixelSize: bounds the longest edge, in *pixels*. Pass the
    ///   point size multiplied by the display scale so Retina output stays crisp.
    public static func thumbnail(contentsOf url: URL, maxPixelSize: Int) throws -> CGImage {
        // `kCGImageSourceShouldCache: false` — we only want the thumbnail, so
        // don't let the source hold the full-size decode too.
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw AIShotError.encodingFailed("could not read image at \(url.lastPathComponent)")
        }
        return try makeThumbnail(source, maxPixelSize: maxPixelSize)
    }

    /// In-memory variant, for callers that already hold the bytes.
    public static func thumbnail(from data: Data, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AIShotError.encodingFailed("could not read image data")
        }
        return try makeThumbnail(source, maxPixelSize: maxPixelSize)
    }

    private static func makeThumbnail(_ source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Honor EXIF orientation so rotated sources aren't shown sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode here, on this (background) thread. Without it ImageIO defers
            // the pixel decode until first draw — i.e. onto the main thread while
            // the user is scrolling, which is exactly what we're avoiding.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AIShotError.encodingFailed("could not create thumbnail")
        }
        return image
    }
}
