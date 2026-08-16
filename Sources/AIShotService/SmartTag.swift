import Foundation

/// Suggests a project tag from whatever was on screen when a capture was taken.
///
/// The aim is a tag you'd have typed yourself: the app's name normally, and the
/// *site* rather than the browser when you captured a web page — tagging forty
/// screenshots "Safari" is worse than not tagging them.
public enum SmartTag {
    /// Apps whose window title describes a web page, not the app.
    static let browsers: Set<String> = [
        "safari", "google chrome", "chrome", "firefox", "arc", "microsoft edge",
        "brave browser", "opera", "vivaldi", "chromium", "orion", "zen browser",
    ]

    /// Separators browsers put between a page title and the site name.
    private static let separators: [String] = [" — ", " – ", " - ", " · ", " | "]

    /// A tag for a capture, or `nil` if nothing useful could be derived.
    ///
    /// - Parameters:
    ///   - appName: owning application, e.g. "Safari", "Xcode".
    ///   - windowTitle: that window's title, when known.
    public static func suggest(appName: String?, windowTitle: String? = nil) -> String? {
        guard let appName = clean(appName), !appName.isEmpty else { return nil }

        if browsers.contains(appName.lowercased()), let site = site(from: windowTitle, browser: appName) {
            return site
        }
        return appName
    }

    /// Pulls a site name out of a browser window title.
    ///
    /// Titles are overwhelmingly "Page Title <sep> Site", so the last segment is
    /// the site. Firefox and Edge append their own name, which is dropped first.
    static func site(from windowTitle: String?, browser: String) -> String? {
        guard var title = clean(windowTitle), !title.isEmpty else { return nil }

        // Drop a trailing browser name ("… — Mozilla Firefox").
        for separator in separators {
            let parts = title.components(separatedBy: separator)
            if parts.count > 1, let last = parts.last, isBrowserName(last) {
                title = parts.dropLast().joined(separator: separator)
                break
            }
        }

        // The last remaining segment is the site.
        var candidate = title
        for separator in separators {
            if let last = title.components(separatedBy: separator).last, !last.isEmpty {
                let trimmed = last.trimmingCharacters(in: .whitespaces)
                // Prefer the shortest plausible segment across separators.
                if !trimmed.isEmpty, trimmed.count < candidate.count { candidate = trimmed }
            }
        }
        candidate = candidate.trimmingCharacters(in: .whitespaces)

        // A bare domain reads better as its second-level name: "github.com" → "github".
        if candidate.contains("."), !candidate.contains(" ") {
            let parts = candidate.lowercased()
                .replacingOccurrences(of: "www.", with: "")
                .components(separatedBy: ".")
            if parts.count >= 2, let name = parts.first, !name.isEmpty { candidate = name }
        }

        // A whole sentence isn't a tag — fall back to the app name.
        guard !candidate.isEmpty, candidate.count <= 40, !isBrowserName(candidate) else { return nil }
        return candidate
    }

    private static func isBrowserName(_ value: String) -> Bool {
        let lowered = value.trimmingCharacters(in: .whitespaces).lowercased()
        if browsers.contains(lowered) { return true }
        // "Mozilla Firefox", "Google Chrome" etc.
        return browsers.contains { lowered.hasSuffix($0) }
    }

    private static func clean(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
