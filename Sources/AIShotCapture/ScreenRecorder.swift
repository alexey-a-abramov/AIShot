import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import OSLog
import ScreenCaptureKit
import AIShotCore

/// Records a display to an H.264 `.mp4` using `SCStream` frames written through
/// an `AVAssetWriter`.
///
/// Requires Screen Recording permission at runtime. Sample buffers are appended
/// on the stream's delegate queue (never crossing into the actor) so no
/// non-`Sendable` `CMSampleBuffer` leaves its thread.
public actor ScreenRecorder {
    private var stream: SCStream?
    private var sink: RecordingSink?
    private var outputURL: URL?

    public init() {}

    public var isRecording: Bool { stream != nil }

    public func start(displayID: CGDirectDisplayID, to url: URL) async throws {
        guard stream == nil else { throw AIShotError.invalidRequest("recording already in progress") }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw AIShotError.targetNotFound("display \(displayID)")
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let width = Int((filter.contentRect.width * scale).rounded())
        let height = Int((filter.contentRect.height * scale).rounded())

        let config = SCStreamConfiguration()
        config.width = max(2, width)
        config.height = max(2, height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 6

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw AIShotError.captureFailed("cannot add video input") }
        writer.add(input)

        let sink = RecordingSink(writer: writer, input: input)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.aishot.recorder"))

        self.stream = stream
        self.sink = sink
        self.outputURL = url

        try await stream.startCapture()
    }

    @discardableResult
    public func stop() async throws -> URL {
        guard let stream, let sink, let url = outputURL else {
            throw AIShotError.invalidRequest("no recording in progress")
        }
        try await stream.stopCapture()
        await sink.finish()
        self.stream = nil
        self.sink = nil
        self.outputURL = nil
        return url
    }
}

/// `SCStreamOutput` that appends frames directly on the delegate queue,
/// serialized by a lock. Marked `@unchecked Sendable` because all mutable state
/// is lock-protected.
private final class RecordingSink: NSObject, SCStreamOutput, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let lock = NSLock()

    init(writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.writer = writer
        self.input = input
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        lock.lock()
        defer { lock.unlock() }
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        if writer.status == .writing, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    /// Called only after `SCStream.stopCapture()` has returned, so no further
    /// delegate callbacks race with this.
    func finish() async {
        if writer.status == .writing { input.markAsFinished() }
        await writer.finishWriting()
    }
}
