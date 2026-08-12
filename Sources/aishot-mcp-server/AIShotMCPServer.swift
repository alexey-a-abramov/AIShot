import Foundation
import MCP
import AIShotCapture
import AIShotPersistence
import AIShotService
import AIShotMCP

/// Standalone MCP server over stdio. Agents register it with, e.g.:
///
///     claude mcp add aishot -- /path/to/aishot-mcp-server
///
/// This is a separate process from the app, so it deliberately reads the *app's*
/// state rather than its own:
///
/// - settings from the app's preference domain, so the "Enable MCP server" and
///   "Confirm before clicks/typing" switches actually govern it;
/// - history and the search index from `DataPaths`, so `get_history` and
///   `search_captures` see the user's real captures instead of an empty store.
///
/// Capture, enumeration, and read tools work headless. Tools that synthesize
/// input can't ask for confirmation here (there's no UI), so they're refused
/// unless the user has turned the confirmation requirement off.
@main
struct AIShotMCPServerMain {
    /// The app's preference domain — must match `PRODUCT_BUNDLE_IDENTIFIER`.
    static let appDomain = "com.aishot.app"

    static func main() async {
        let settingsStore = UserDefaultsSettingsStore(appDomain: appDomain)
        let capture = CaptureService(
            engine: ScreenCaptureKitEngine(),
            settingsStore: settingsStore,
            history: FileHistoryStore(fileURL: DataPaths.historyFile)
        )
        let service = ScreenshotMCPService(
            capture: capture,
            textIndexer: TextIndexer(store: CaptureTextIndexStore(fileURL: DataPaths.textIndexFile)),
            // Re-read per call so toggling a switch in the app takes effect
            // without the agent having to reconnect.
            isEnabled: { ((try? settingsStore.load()) ?? .default).mcpEnabled },
            requiresInputConfirmation: {
                ((try? settingsStore.load()) ?? .default).mcpRequireConfirmationForInput
            }
        )
        let host = MCPServerHost(service: service)
        do {
            try await host.start(transport: StdioTransport())
            await host.waitUntilCompleted()
        } catch {
            FileHandle.standardError.write(Data("AIShot MCP server failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
