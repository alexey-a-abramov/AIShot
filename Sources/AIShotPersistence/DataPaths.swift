import Foundation

/// Locations of AIShot's app-managed data files.
///
/// Lives in the shared package rather than the app target because the app and
/// the standalone MCP helper are **separate processes that must agree on these
/// paths** — otherwise an agent reads an empty history and an empty search
/// index while the app happily writes to its own.
public enum DataPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AIShot", isDirectory: true)
    }

    /// Capture history (screenshots and recordings).
    public static var historyFile: URL {
        supportDirectory.appendingPathComponent("history.json")
    }

    /// Full-text (OCR) search index. Derived data — safe to delete; it rebuilds
    /// in the background.
    public static var textIndexFile: URL {
        supportDirectory.appendingPathComponent("text-index.json")
    }
}
