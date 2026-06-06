import CoreGraphics
import Foundation
import AIShotCore

/// Captures a region repeatedly while scrolling, then stitches the frames into
/// one tall image (Snagit/Shottr-style scrolling screenshot).
///
/// Requires Screen Recording (capture) and Accessibility (synthetic scroll) at
/// runtime. Overlap is estimated as a fraction of the frame height; precise
/// feature-matched overlap is a future enhancement.
public actor ScrollingCapture {
    private let engine: ScreenCaptureKitEngine

    public init(engine: ScreenCaptureKitEngine = ScreenCaptureKitEngine()) {
        self.engine = engine
    }

    public func capture(
        displayID: CGDirectDisplayID,
        rect: CGRect,
        frames: Int = 8,
        overlapFraction: Double = 0.12,
        scrollLines: Int = 6
    ) async throws -> Data {
        let count = max(1, frames)
        var shots: [Data] = []
        for index in 0..<count {
            let image = try await engine.capture(
                CaptureRequest(mode: .region, displayID: displayID, rect: rect, format: .png)
            )
            shots.append(image.data)
            if index < count - 1 {
                Self.scroll(at: CGPoint(x: rect.midX, y: rect.midY), lines: -scrollLines)
                try await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        let firstHeight = (try? ImageCodec.decode(shots[0]))?.height ?? 0
        let overlap = Int(Double(firstHeight) * max(0, min(0.9, overlapFraction)))
        return try ImageStitcher.stitchVertical(shots, overlap: overlap)
    }

    private static func scroll(at point: CGPoint, lines: Int) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
            wheel1: Int32(lines), wheel2: 0, wheel3: 0
        ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }
}
