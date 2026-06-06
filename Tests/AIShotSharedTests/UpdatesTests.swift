import Testing
import Foundation
@testable import AIShotShared

struct VersionCompareTests {
    @Test func comparesNumericallyNotLexically() {
        #expect(VersionCompare.isNewer("1.10.0", than: "1.9.0"))
        #expect(VersionCompare.isNewer("2.0.0", than: "1.9.9"))
        #expect(!VersionCompare.isNewer("1.0.0", than: "1.0.1"))
        #expect(!VersionCompare.isNewer("1.2.0", than: "1.2.0"))
    }
}

struct AppcastTests {
    private let feed = """
    <?xml version="1.0"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item><enclosure url="https://x/AIShot-1.2.0.dmg" sparkle:version="1.2.0" sparkle:shortVersionString="1.2.0"/></item>
        <item><enclosure url="https://x/AIShot-1.1.0.dmg" sparkle:version="1.1.0" sparkle:shortVersionString="1.1.0"/></item>
      </channel>
    </rss>
    """

    @Test func parsesEnclosures() {
        let items = AppcastParser.parse(Data(feed.utf8))
        #expect(items.count == 2)
        #expect(items.first?.version == "1.2.0")
        #expect(items.first?.url?.absoluteString == "https://x/AIShot-1.2.0.dmg")
    }

    @Test func picksNewestNewerThanCurrent() {
        let checker = UpdateChecker(feedURL: URL(string: "https://x/appcast.xml")!, currentVersion: "1.0.0")
        #expect(checker.update(in: Data(feed.utf8))?.version == "1.2.0")
    }

    @Test func returnsNilWhenCurrentIsLatest() {
        let checker = UpdateChecker(feedURL: URL(string: "https://x/appcast.xml")!, currentVersion: "1.2.0")
        #expect(checker.update(in: Data(feed.utf8)) == nil)
    }
}
