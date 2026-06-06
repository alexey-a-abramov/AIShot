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
/// Capture/enumeration/history tools work headless; privileged input tools are
/// denied by default (no confirmation UI in a headless process).
@main
struct AIShotMCPServerMain {
    static func main() async {
        let capture = CaptureService(
            engine: ScreenCaptureKitEngine(),
            settingsStore: UserDefaultsSettingsStore(),
            history: InMemoryHistoryStore()
        )
        let service = ScreenshotMCPService(capture: capture)
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
