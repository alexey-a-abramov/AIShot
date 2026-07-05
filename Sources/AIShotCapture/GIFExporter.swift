import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AIShotCore

/// Transcodes a recorded video into an animated GIF by sampling frames at a
/// fixed rate and encoding them with ImageIO — no external tools or extra
/// dependencies, consistent with the rest of AIShot's capture pipeline.
public struct GIFExporter: Sendable {
    public init() {}

    /// Samples `videoURL` at `fps` (downscaling to `maxDimension` on the long
    /// edge to keep file size reasonable) and writes an animated, looping GIF
    /// to a sibling file with a `.gif` extension. Throws if the video has no
    /// usable duration or the GIF can't be finalized.
    ///
    /// Runs the actual decode/encode loop off the caller's executor (frame
    /// decoding is synchronous, CPU-bound work) so awaiting this from the
    /// main actor doesn't stall the UI for the length of the recording.
    public func export(videoURL: URL, fps: Double = 8, maxDimension: CGFloat = 800) async throws -> URL {
        try await Task.detached(priority: .utility) {
            try await Self.encode(videoURL: videoURL, fps: fps, maxDimension: maxDimension)
        }.value
    }

    private static func encode(videoURL: URL, fps: Double, maxDimension: CGFloat) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw AIShotError.captureFailed("recording has no usable duration")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let frameInterval = 1.0 / max(fps, 1)
        var times: [CMTime] = []
        var t = 0.0
        while t < duration {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += frameInterval
        }
        guard !times.isEmpty else { throw AIShotError.captureFailed("no frames to sample") }

        let outputURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
        try? FileManager.default.removeItem(at: outputURL)
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.gif.identifier as CFString, times.count, nil
        ) else {
            throw AIShotError.encodingFailed("could not create GIF destination")
        }

        let frameProperties: CFDictionary = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameInterval,
            ],
        ] as CFDictionary

        var framesWritten = 0
        for time in times {
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            CGImageDestinationAddImage(destination, scaled(cgImage, maxDimension: maxDimension), frameProperties)
            framesWritten += 1
        }
        guard framesWritten > 0 else { throw AIShotError.captureFailed("no frames could be decoded") }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0],
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw AIShotError.encodingFailed("GIF finalize failed")
        }
        return outputURL
    }

    /// Downscales to `maxDimension` on the long edge; returns the original
    /// image unchanged if it's already smaller.
    private static func scaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let scale = min(1, maxDimension / max(width, height, 1))
        guard scale < 1,
              let space = image.colorSpace,
              let ctx = CGContext(
                data: nil,
                width: max(1, Int((width * scale).rounded())),
                height: max(1, Int((height * scale).rounded())),
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width * scale, height: height * scale))
        return ctx.makeImage() ?? image
    }
}
