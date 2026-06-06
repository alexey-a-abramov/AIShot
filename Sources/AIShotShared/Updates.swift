import Foundation

/// One entry from a Sparkle-style appcast feed.
public struct AppcastItem: Sendable, Equatable {
    public let version: String
    public let shortVersion: String?
    public let url: URL?

    public init(version: String, shortVersion: String? = nil, url: URL? = nil) {
        self.version = version
        self.shortVersion = shortVersion
        self.url = url
    }
}

/// Dotted numeric version comparison (e.g. `1.2.0` vs `1.10.0`).
public enum VersionCompare {
    public static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let a = parts(lhs)
        let b = parts(rhs)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ string: String) -> [Int] {
        string.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
    }
}

/// Parses a Sparkle-style appcast (RSS) for `<item>` enclosures.
public enum AppcastParser {
    public static func parse(_ data: Data) -> [AppcastItem] {
        let delegate = CollectingDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    private final class CollectingDelegate: NSObject, XMLParserDelegate {
        var items: [AppcastItem] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String]
        ) {
            guard elementName == "enclosure" else { return }
            let version = attributeDict["sparkle:version"]
                ?? attributeDict["sparkle:shortVersionString"]
            guard let version else { return }
            items.append(AppcastItem(
                version: version,
                shortVersion: attributeDict["sparkle:shortVersionString"],
                url: attributeDict["url"].flatMap(URL.init(string:))
            ))
        }
    }
}

/// Checks an appcast feed for a version newer than `currentVersion`. Dependency
/// free; Sparkle remains the optional full-installer path (see RELEASING.md).
public struct UpdateChecker: Sendable {
    public let feedURL: URL
    public let currentVersion: String

    public init(feedURL: URL, currentVersion: String) {
        self.feedURL = feedURL
        self.currentVersion = currentVersion
    }

    /// The newest available update in `data`, or nil if none is newer.
    public func update(in data: Data) -> AppcastItem? {
        AppcastParser.parse(data)
            .filter { VersionCompare.isNewer($0.version, than: currentVersion) }
            .max { VersionCompare.isNewer($1.version, than: $0.version) }
    }

    /// Fetches the feed and returns an available update, if any.
    public func check(session: URLSession = .shared) async throws -> AppcastItem? {
        let (data, _) = try await session.data(from: feedURL)
        return update(in: data)
    }
}
