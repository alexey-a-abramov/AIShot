import Foundation

/// Filesystem locations for app-managed data (history index, etc.).
enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AIShot", isDirectory: true)
    }

    static var historyFile: URL {
        supportDirectory.appendingPathComponent("history.json")
    }
}
