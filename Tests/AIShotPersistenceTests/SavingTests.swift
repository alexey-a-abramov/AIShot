import Testing
import Foundation
@testable import AIShotPersistence


/// The save path must never report success for a file that isn't there.
///
/// Regression: `UNNotificationAttachment` takes ownership of the file it's
/// handed and moves it into the notification store, so every captured PNG was
/// deleted moments after being written — while history kept a row pointing at
/// it, producing "File missing" cards with no explanation anywhere.
struct CaptureSaverVerificationTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-verify-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func savingWritesTheBytesAndReportsThePath() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try CaptureSaver().save(Data([0x89, 0x50, 0x4E, 0x47]), fileName: "a.png", to: dir)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url).count == 4)
    }

    /// An empty capture means the engine produced nothing; writing it would
    /// leave an unopenable file and a history row pointing at it.
    @Test func anEmptyCaptureIsRefusedRatherThanWritten() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: CaptureSaveError.emptyImage) {
            try CaptureSaver().save(Data(), fileName: "empty.png", to: dir)
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("empty.png").path))
    }

    @Test func anUnwritableDirectoryThrowsInsteadOfReturningAPath() {
        // /dev/null is a file, so creating a directory beneath it always fails.
        #expect(throws: (any Error).self) {
            try CaptureSaver().save(Data([1]), fileName: "x.png",
                                    to: URL(fileURLWithPath: "/dev/null/nope", isDirectory: true))
        }
    }
}
