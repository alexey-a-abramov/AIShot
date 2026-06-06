import Testing
import Foundation
import CoreGraphics
import MCP
@testable import AIShotMCP
@testable import AIShotCore
@testable import AIShotCapture
@testable import AIShotService
@testable import AIShotPersistence

private struct FakeCapturing: ScreenCapturing {
    func availableDisplays() async throws -> [DisplayInfo] {
        [DisplayInfo(id: 1, name: "D1", frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2, isMain: true)]
    }
    func availableWindows() async throws -> [WindowInfo] { [] }
    func capture(_ request: CaptureRequest) async throws -> CapturedImage {
        CapturedImage(pixelSize: CGSize(width: 10, height: 8), scale: 2, format: .png, data: Data([0x89, 0x50, 0x4E, 0x47]))
    }
}

private struct FakeSettingsStore: SettingsStore {
    let settings: AppSettings
    func load() throws -> AppSettings { settings }
    func save(_ settings: AppSettings) throws {}
}

private func makeService() -> ScreenshotMCPService {
    var settings = AppSettings.default
    settings.saveDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aishot-mcp-\(UUID().uuidString)", isDirectory: true)
    settings.copyToClipboard = false
    settings.showNotification = false
    let capture = CaptureService(
        engine: FakeCapturing(),
        settingsStore: FakeSettingsStore(settings: settings),
        history: InMemoryHistoryStore()
    )
    return ScreenshotMCPService(capture: capture)
}

private func hasImage(_ content: [Tool.Content]) -> Bool {
    content.contains { if case .image = $0 { return true } else { return false } }
}

struct MCPServiceTests {
    @Test func toolDefinitionsMatchCatalog() {
        let tools = makeService().toolDefinitions()
        #expect(tools.count == MCPTool.allCases.count)
        #expect(tools.contains { $0.name == "capture_display" })
        #expect(tools.allSatisfy { !($0.description ?? "").isEmpty })
    }

    @Test func listDisplaysReturnsContent() async {
        let result = await makeService().call(name: "list_displays", arguments: nil)
        #expect(result.isError != true)
        #expect(!result.content.isEmpty)
    }

    @Test func captureDisplayReturnsImage() async {
        let result = await makeService().call(name: "capture_display", arguments: ["displayID": 1])
        #expect(result.isError != true)
        #expect(hasImage(result.content))
    }

    @Test func privilegedToolDeniedWithoutConfirmation() async {
        let result = await makeService().call(name: "click", arguments: ["x": 10, "y": 20])
        #expect(result.isError == true)
    }

    @Test func unknownToolIsError() async {
        let result = await makeService().call(name: "does_not_exist", arguments: nil)
        #expect(result.isError == true)
    }

    @Test func roundTripOverInMemoryTransport() async throws {
        let host = MCPServerHost(service: makeService())
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        try await host.start(transport: serverTransport)

        let client = Client(name: "test-client", version: "1.0")
        _ = try await client.connect(transport: clientTransport)

        let (tools, _) = try await client.listTools()
        #expect(tools.contains { $0.name == "capture_display" })

        let (content, isError) = try await client.callTool(name: "capture_display", arguments: ["displayID": 1])
        #expect(isError != true)
        #expect(hasImage(content))

        await host.stop()
    }
}
