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
}
