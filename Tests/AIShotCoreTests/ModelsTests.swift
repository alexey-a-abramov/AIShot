import Testing
import CoreGraphics
import Foundation
@testable import AIShotCore

struct ModelsTests {
    @Test func imageFormatExtensionsAndUTTypes() {
        #expect(ImageFormat.png.fileExtension == "png")
        #expect(ImageFormat.jpeg.fileExtension == "jpg")
        #expect(ImageFormat.heic.utTypeIdentifier == "public.heic")
        #expect(ImageFormat.allCases.count == 4)
    }

    @Test func captureModeCoversExpectedCases() {
        #expect(Set(CaptureMode.allCases.map(\.rawValue)) == ["region", "window", "display", "allDisplays"])
    }

    @Test func captureRequestRoundTripsThroughJSON() throws {
        let request = CaptureRequest(
            mode: .region,
            displayID: 1,
            rect: CGRect(x: 0, y: 0, width: 100, height: 50),
            includeCursor: true,
            format: .heic,
            delay: 3
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CaptureRequest.self, from: data)
        #expect(decoded == request)
    }

    @Test func captureRequestDefaultsAreSafe() {
        let request = CaptureRequest(mode: .window)
        #expect(request.includeCursor == false)
        #expect(request.includeWindowShadow == true)
        #expect(request.format == .png)
        #expect(request.delay == 0)
    }
}
