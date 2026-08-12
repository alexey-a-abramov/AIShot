import Testing
import Foundation
@testable import AIShotPersistence

struct SaveDestinationResolverTests {
    private let resolver = SaveDestinationResolver()
    private let root = URL(fileURLWithPath: "/Users/me/Pictures/AIShot", isDirectory: true)
    /// 2026-08-06 UTC, fixed so folder names are deterministic.
    private let date = Date(timeIntervalSince1970: 1_786_000_000)
    private let utc = TimeZone(identifier: "UTC")!

    private func settings(
        _ organization: FolderOrganization,
        granularity: DateFolderGranularity = .month,
        untagged: String = "Unsorted"
    ) -> AppSettings {
        var s = AppSettings.default
        s.saveDirectory = root
        s.folderOrganization = organization
        s.dateFolderGranularity = granularity
        s.untaggedFolderName = untagged
        return s
    }

    private func subpath(_ organization: FolderOrganization, tag: String?,
                         granularity: DateFolderGranularity = .month,
                         untagged: String = "Unsorted") -> [String] {
        resolver.resolve(settings: settings(organization, granularity: granularity, untagged: untagged),
                         tag: tag, date: date, timeZone: utc).subpath
    }

    @Test func noneKeepsEverythingInTheRoot() {
        let resolved = resolver.resolve(settings: settings(.none), tag: "ProjectX",
                                        date: date, timeZone: utc)
        #expect(resolved.subpath.isEmpty)
        #expect(resolved.directory == root)
    }

    @Test func byDateUsesTheConfiguredGranularity() {
        #expect(subpath(.byDate, tag: nil, granularity: .day) == ["2026-08-06"])
        #expect(subpath(.byDate, tag: nil, granularity: .month) == ["2026-08"])
        #expect(subpath(.byDate, tag: nil, granularity: .year) == ["2026"])
    }

    @Test func byTagUsesTheTag() {
        #expect(subpath(.byTag, tag: "ProjectX") == ["ProjectX"])
    }

    @Test func tagFolderSitsAboveDateSoAProjectStaysOneFolder() {
        #expect(subpath(.byTagThenDate, tag: "ProjectX") == ["ProjectX", "2026-08"])
    }

    @Test func missingOrBlankTagFallsBackToTheUntaggedFolder() {
        #expect(subpath(.byTag, tag: nil) == ["Unsorted"])
        #expect(subpath(.byTag, tag: "   ") == ["Unsorted"])
        #expect(subpath(.byTag, tag: "x", untagged: "") == ["x"])
        // A blank untagged name still yields a usable folder.
        #expect(subpath(.byTag, tag: nil, untagged: "  ") == ["Unsorted"])
    }

    /// A tag is user input: it must never become two directory levels.
    @Test func separatorsInATagCollapseToOneComponent() {
        let path = subpath(.byTag, tag: "a/b")
        #expect(path.count == 1)
        #expect(!path[0].contains("/"))
    }

    /// The important one: a tag must not be able to escape the library root.
    @Test func dotSegmentsCannotEscapeTheRoot() {
        for evil in ["..", ".", "../..", "../../etc"] {
            let resolved = resolver.resolve(settings: settings(.byTag), tag: evil,
                                            date: date, timeZone: utc)
            #expect(resolved.directory.path.hasPrefix(root.path),
                    "\(evil) escaped to \(resolved.directory.path)")
            #expect(!resolved.subpath.contains(".."))
        }
    }

    @Test func hiddenFoldersAreNotCreatedFromLeadingDots() {
        #expect(subpath(.byTag, tag: ".secret") == ["secret"])
    }

    @Test func veryLongTagsAreCapped() {
        let long = String(repeating: "x", count: 300)
        let component = subpath(.byTag, tag: long)[0]
        #expect(component.utf8.count <= SaveDestinationResolver.maxComponentBytes)
    }

    @Test func emojiTagsSurvive() {
        #expect(subpath(.byTag, tag: "🚀 Launch") == ["🚀 Launch"])
    }

    @Test func rootOverrideWins() {
        let other = URL(fileURLWithPath: "/Volumes/Work/Shots", isDirectory: true)
        let resolved = resolver.resolve(settings: settings(.byDate), tag: nil,
                                        date: date, rootOverride: other, timeZone: utc)
        #expect(resolved.root == other)
        #expect(resolved.directory.path.hasPrefix(other.path))
    }

    /// A one-off Save As… must not silently redirect later automatic saves.
    @Test func lastSaveAsDirectoryNeverAffectsResolution() {
        var s = settings(.none)
        s.lastSaveAsDirectory = URL(fileURLWithPath: "/tmp/elsewhere", isDirectory: true)
        let resolved = resolver.resolve(settings: s, tag: nil, date: date, timeZone: utc)
        #expect(resolved.directory == root)
    }

    /// Resolution is pure — it must not touch the filesystem.
    @Test func resolutionCreatesNoDirectories() {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("aishot-resolve-\(UUID().uuidString)", isDirectory: true)
        var s = settings(.byTagThenDate)
        s.saveDirectory = scratch
        let resolved = resolver.resolve(settings: s, tag: "P", date: date, timeZone: utc)
        #expect(!FileManager.default.fileExists(atPath: resolved.directory.path))
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }

    /// Folder names must stay Gregorian/ASCII regardless of the user's region.
    @Test func dateFolderIsGregorianUnderANonGregorianLocale() {
        var s = settings(.byDate)
        s.saveDirectory = root
        let thai = TimeZone(identifier: "Asia/Bangkok")!
        let component = resolver.resolve(settings: s, tag: nil, date: date, timeZone: thai).subpath[0]
        #expect(component.hasPrefix("2026"))
    }
}
