import Foundation

/// Facts about this build, in one place.
///
/// The About window and the Settings About page both display these; keeping a
/// single source stops the two from drifting apart, which is exactly what
/// happens when a version string or a copyright year is typed twice.
enum AppInfo {
    static let name = "AIShot"
    static let author = "Alexey Abramov"
    static let licenseName = "Apache License 2.0"
    /// Year of first publication, used in the copyright line.
    static let copyrightYear = "2026"

    static let repositoryURL = URL(string: "https://github.com/alexey-a-abramov/AIShot")!
    /// Shown as the link's text — the bare URL is noise in a small window.
    static let repositoryLabel = "github.com/alexey-a-abramov/AIShot"
    static let licenseURL = URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!

    /// Human-facing release version, e.g. "0.0.1".
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Build number — the git commit count, stamped at project generation.
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// "0.0.1 (61)" — the form worth pasting into a bug report.
    static var versionString: String { "\(version) (\(build))" }

    static var copyright: String { "© \(copyrightYear) \(author)" }
}
