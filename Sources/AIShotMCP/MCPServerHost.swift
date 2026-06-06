import Foundation
import MCP

/// Hosts the MCP `Server`, registering the AIShot tool handlers and running over
/// any transport (stdio for a spawned agent process, loopback HTTP in-app, or
/// `InMemoryTransport` for tests).
public actor MCPServerHost {
    private let service: ScreenshotMCPService
    private let server: Server

    public init(service: ScreenshotMCPService, name: String = "AIShot", version: String = "0.1.0") {
        self.service = service
        self.server = Server(
            name: name,
            version: version,
            capabilities: .init(
                prompts: .init(listChanged: false),
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: false)
            )
        )
    }

    /// Registers handlers and starts serving on `transport`.
    public func start(transport: any Transport) async throws {
        let service = self.service
        _ = await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: service.toolDefinitions())
        }
        _ = await server.withMethodHandler(CallTool.self) { params in
            await service.call(name: params.name, arguments: params.arguments)
        }
        _ = await server.withMethodHandler(ListResources.self) { _ in
            ListResources.Result(resources: await service.resourceList())
        }
        _ = await server.withMethodHandler(ReadResource.self) { params in
            await service.readResource(uri: params.uri)
        }
        try await server.start(transport: transport)
    }

    /// Blocks until the server's run loop completes (used by the CLI entry point).
    public func waitUntilCompleted() async {
        await server.waitUntilCompleted()
    }

    public func stop() async {
        await server.stop()
    }
}
