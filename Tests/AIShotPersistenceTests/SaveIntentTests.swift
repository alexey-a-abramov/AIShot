import Testing
import Foundation
@testable import AIShotPersistence
@testable import AIShotCore

struct SaveIntentTests {
    private let date = Date(timeIntervalSince1970: 1_786_000_000)
    private func settings() -> AppSettings {
        var s = AppSettings.default
        s.saveDirectory = URL(fileURLWithPath: "/Users/me/Shots", isDirectory: true)
        return s
    }

    private func intent(source: URL?, exists: Bool = true, overwrite: Bool = true) -> SaveIntent {
        resolveSaveIntent(sourceURL: source, sourceExists: exists, overwriteEnabled: overwrite,
                          settings: settings(), tag: nil, date: date,
                          timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test func overwritesWhenTheSourceIsAWritableImage() {
        let url = URL(fileURLWithPath: "/Users/me/Shots/a.png")
        #expect(intent(source: url) == .overwrite(url, format: .png))
    }

    @Test func carriesTheSourceFormatSoTheFileKeepsItsType() {
        let url = URL(fileURLWithPath: "/Users/me/Shots/a.JPEG")
        #expect(intent(source: url) == .overwrite(url, format: .jpeg))
    }

    @Test func writesANewFileWhenThereIsNoSource() {
        guard case .newFile = intent(source: nil) else {
            Issue.record("expected .newFile"); return
        }
    }

    /// The file was deleted or moved behind our back — don't recreate it there.
    @Test func writesANewFileWhenTheSourceIsGone() {
        let url = URL(fileURLWithPath: "/Users/me/Shots/a.png")
        guard case .newFile = intent(source: url, exists: false) else {
            Issue.record("expected .newFile"); return
        }
    }

    @Test func writesANewFileWhenOverwriteIsTurnedOff() {
        let url = URL(fileURLWithPath: "/Users/me/Shots/a.png")
        guard case .newFile = intent(source: url, overwrite: false) else {
            Issue.record("expected .newFile"); return
        }
    }

    /// Editing a frame of a recording must not clobber the recording.
    @Test func neverOverwritesANonImageSource() {
        for ext in ["mp4", "mov", "gif"] {
            let url = URL(fileURLWithPath: "/Users/me/Shots/a.\(ext)")
            guard case .newFile = intent(source: url) else {
                Issue.record("expected .newFile for .\(ext)"); return
            }
        }
    }

    @Test func newFileHonoursFolderOrganization() {
        var s = settings()
        s.folderOrganization = .byTag
        let result = resolveSaveIntent(sourceURL: nil, sourceExists: false, overwriteEnabled: true,
                                       settings: s, tag: "ProjectX", date: date,
                                       timeZone: TimeZone(identifier: "UTC")!)
        guard case .newFile(let directory, _) = result else {
            Issue.record("expected .newFile"); return
        }
        #expect(directory.lastPathComponent == "ProjectX")
    }
}
