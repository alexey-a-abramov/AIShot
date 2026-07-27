import Foundation
import AIShotPersistence

/// Filesystem locations for app-managed data.
///
/// These forward to `DataPaths` in the shared package: the standalone MCP
/// helper is a separate process that must resolve the *same* files, so the
/// definitions can't live only in the app target.
enum AppPaths {
    static var supportDirectory: URL { DataPaths.supportDirectory }
    static var historyFile: URL { DataPaths.historyFile }
    static var textIndexFile: URL { DataPaths.textIndexFile }
}
