import Testing
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
@testable import AIShotCapture
@testable import AIShotCore

struct GIFExporterTests {
    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("aishot-gif-\(UUID().uuidString)-\(name)")
    }

    /// Writes a tiny synthetic `.mp4` (a handful of solid-color frames) with no
    /// screen-recording permission required, so `GIFExporter` can be exercised
    /// end-to-end in CI.
    private func makeTestVideo(frameCount: Int = 6, size: Int = 32) async throws -> URL {
        let url = tempURL("source.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size,
            AVVideoHeightKey: size,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: size,
                kCVPixelBufferHeightKey as String: size,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw AIShotError.captureFailed("no pixel buffer pool") }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else { throw AIShotError.captureFailed("no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let byteCount = CVPixelBufferGetDataSize(buffer)
                memset(base, i.isMultiple(of: 2) ? 0xFF : 0x00, byteCount)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: CMTimeValue(i), timescale: 4) // 4 fps source
            adaptor.append(buffer, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    @Test func exportsPlayableAnimatedGIF() async throws {
        let video = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: video) }

        let gifURL = try await GIFExporter().export(videoURL: video, fps: 4, maxDimension: 64)
        defer { try? FileManager.default.removeItem(at: gifURL) }

        #expect(gifURL.pathExtension == "gif")
        #expect(FileManager.default.fileExists(atPath: gifURL.path))

        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
            Issue.record("could not open exported GIF")
            return
        }
        #expect(CGImageSourceGetCount(source) > 1) // more than one frame = animated
        let type = CGImageSourceGetType(source) as String?
        #expect(type == "com.compuserve.gif")
    }

    @Test func throwsForUnreadableVideo() async throws {
        let missing = tempURL("does-not-exist.mp4")
        await #expect(throws: (any Error).self) {
            _ = try await GIFExporter().export(videoURL: missing)
        }
    }
}
