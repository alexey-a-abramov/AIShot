import Foundation
import AIShotCore
import AIShotCapture
import AIShotAnnotation
import AIShotAutomation
import AIShotPersistence
import AIShotShared

/// Bridges MCP tool invocations onto the capture / annotation / automation
/// engines. The official `swift-sdk` `Server` (stdio + loopback HTTP) wraps
/// this in Phase P1b; keeping the mapping here makes it transport-agnostic and
/// unit-testable without a live MCP connection.
public actor ScreenshotMCPService {
    private let capture: any ScreenCapturing
    private let automation: AutomationEngine
    private let locator: any ElementLocating
    private let renderer: any AnnotationRendering

    public init(
        capture: any ScreenCapturing = ScreenCaptureKitEngine(),
        automation: AutomationEngine = AutomationEngine(),
        locator: any ElementLocating = VisionElementLocator(),
        renderer: any AnnotationRendering = CoreImageAnnotationRenderer()
    ) {
        self.capture = capture
        self.automation = automation
        self.locator = locator
        self.renderer = renderer
    }

    /// Tools advertised to agents (filtered by settings at registration time).
    public nonisolated func availableTools() -> [MCPTool] {
        MCPTool.allCases
    }

    /// Dispatches a decoded tool call. Real argument decoding + result encoding
    /// land with the transport in P1b; the engines themselves arrive in
    /// P1a/P1c/P1d.
    public func handle(tool: MCPTool, argumentsJSON: Data) async throws -> Data {
        throw AIShotError.notImplemented("ScreenshotMCPService.handle(\(tool.rawValue)) (P1b)")
    }
}
