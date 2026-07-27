import AVFoundation
import CoreGraphics
import Foundation
import AIShotCore

/// Extracts a still frame from a recorded video, so recordings can show a real
/// preview in the dashboard instead of a generic placeholder.
public enum VideoThumbnail: Sendable {
    /// Grabs a representative frame, downscaled so the longest edge is at most
    /// `maxPixelSize` pixels.
    ///
    /// Samples slightly into the clip rather than exactly t=0: the first frame
    /// of a screen recording is often captured mid-fade or before the content
    /// settles, which makes for a poor preview.
    public static func frame(contentsOf url: URL, maxPixelSize: Int) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let sampleAt = duration.isFinite && duration > 0.5 ? min(0.5, duration / 2) : 0

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        // Bounded, not infinite: infinite tolerance lets the generator return
        // the t=0 keyframe, which is the mid-fade frame we're trying to skip.
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let time = CMTime(seconds: sampleAt, preferredTimescale: 600)
        do {
            return try await generator.image(at: time).image
        } catch {
            throw AIShotError.encodingFailed("could not read a frame from \(url.lastPathComponent)")
        }
    }

    /// The video's natural pixel dimensions, for recording history entries.
    /// Returns `nil` if the file has no video track.
    public static func pixelSize(contentsOf url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        // Apply the track transform so a rotated recording reports the size it
        // actually displays at.
        let displayed = size.applying(transform)
        return CGSize(width: abs(displayed.width), height: abs(displayed.height))
    }
}
