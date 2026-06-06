import CoreGraphics
import Foundation
import MCP
import AIShotCore
import AIShotCapture
import AIShotAnnotation
import AIShotAutomation
import AIShotPersistence
import AIShotService

/// Confirmation gate for privileged (synthetic input / app control) tools.
/// Returns `true` to allow. Default implementations deny for safety.
public typealias InputConfirmation = @Sendable (MCPTool, String) async -> Bool

/// Bridges MCP tool invocations onto the capture / annotation / automation
/// engines. Transport-agnostic (used by `MCPServerHost` over stdio or HTTP) and
/// unit-testable without a live connection.
public actor ScreenshotMCPService {
    private let capture: CaptureService
    private let automation: AutomationEngine
    private let locator: any ElementLocating
    private let renderer: any AnnotationRendering
    private let recognizer: TextRecognizer
    private let confirmInput: InputConfirmation

    public init(
        capture: CaptureService,
        automation: AutomationEngine = AutomationEngine(),
        locator: any ElementLocating = VisionElementLocator(),
        renderer: any AnnotationRendering = CoreImageAnnotationRenderer(),
        recognizer: TextRecognizer = TextRecognizer(),
        confirmInput: @escaping InputConfirmation = { _, _ in false }
    ) {
        self.capture = capture
        self.automation = automation
        self.locator = locator
        self.renderer = renderer
        self.recognizer = recognizer
        self.confirmInput = confirmInput
    }

    /// Tool definitions advertised to agents.
    public nonisolated func toolDefinitions() -> [Tool] {
        MCPTool.allCases.map {
            Tool(name: $0.rawValue, description: $0.summary, inputSchema: ToolSchemas.schema(for: $0))
        }
    }

    /// Dispatches a tool call to the right engine and encodes the result.
    public func call(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        guard let tool = MCPTool(rawValue: name) else {
            return Self.error("unknown tool: \(name)")
        }
        do {
            switch tool {
            case .listDisplays: return try await json(capture.displays())
            case .listWindows: return try await json(capture.windows())
            case .listApps: return try await json(automation.runningApps())
            case .getHistory: return try await json(capture.recentHistory(limit: arguments?["limit"]?.intValue ?? 20))
            case .captureRegion: return try await runCapture(regionRequest(arguments))
            case .captureWindow: return try await runCapture(windowRequest(arguments))
            case .captureDisplay: return try await runCapture(displayRequest(arguments))
            case .annotate: return try await runAnnotate(arguments)
            case .locate: return try await runLocate(arguments)
            case .ocr: return try await runOCR(arguments)
            case .switchApp, .click, .typeText: return try await runPrivileged(tool, arguments)
            }
        } catch {
            return Self.error("\(error)")
        }
    }

    // MARK: - Capture

    private func runCapture(_ request: CaptureRequest) async throws -> CallTool.Result {
        let outcome = try await capture.performCapture(request)
        let image = outcome.image
        let meta: [String: Value] = [
            "path": .string(outcome.result.fileURL?.path ?? ""),
            "width": .int(Int(image.pixelSize.width)),
            "height": .int(Int(image.pixelSize.height)),
            "scale": .double(Double(image.scale)),
            "format": .string(image.format.rawValue),
        ]
        return CallTool.Result(content: [
            .image(data: image.data.base64EncodedString(), mimeType: image.format.mimeType, annotations: nil, _meta: nil),
            .text(text: Self.jsonString(.object(meta)), annotations: nil, _meta: nil),
        ])
    }

    private func regionRequest(_ args: [String: Value]?) throws -> CaptureRequest {
        guard let display = args?["displayID"]?.intValue, let rect = args?["rect"]?.objectValue else {
            throw AIShotError.invalidRequest("capture_region requires displayID and rect")
        }
        func value(_ key: String) -> CGFloat {
            CGFloat(rect[key]?.doubleValue ?? Double(rect[key]?.intValue ?? 0))
        }
        return CaptureRequest(
            mode: .region,
            displayID: UInt32(display),
            rect: CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height")),
            includeCursor: args?["includeCursor"]?.boolValue ?? false,
            format: imageFormat(args)
        )
    }

    private func windowRequest(_ args: [String: Value]?) throws -> CaptureRequest {
        guard let id = args?["windowID"]?.intValue else {
            throw AIShotError.invalidRequest("capture_window requires windowID")
        }
        return CaptureRequest(
            mode: .window,
            windowID: UInt32(id),
            includeWindowShadow: args?["includeWindowShadow"]?.boolValue ?? true,
            format: imageFormat(args)
        )
    }

    private func displayRequest(_ args: [String: Value]?) throws -> CaptureRequest {
        guard let id = args?["displayID"]?.intValue else {
            throw AIShotError.invalidRequest("capture_display requires displayID")
        }
        return CaptureRequest(mode: .display, displayID: UInt32(id), format: imageFormat(args))
    }

    private func imageFormat(_ args: [String: Value]?) -> ImageFormat {
        if let raw = args?["format"]?.stringValue, let format = ImageFormat(rawValue: raw) { return format }
        return .png
    }

    // MARK: - Annotate

    private func runAnnotate(_ args: [String: Value]?) async throws -> CallTool.Result {
        let base: Data
        if let b64 = args?["imageBase64"]?.stringValue, let data = Data(base64Encoded: b64) {
            base = data
        } else if let path = args?["imagePath"]?.stringValue {
            base = try Data(contentsOf: URL(fileURLWithPath: path))
        } else {
            throw AIShotError.invalidRequest("annotate requires imageBase64 or imagePath")
        }
        let document = try AnnotationDecoding.document(from: args?["annotations"], basePNG: base)
        let rendered = try await renderer.render(document, onto: base)
        return CallTool.Result(content: [
            .image(data: rendered.base64EncodedString(), mimeType: ImageFormat.png.mimeType, annotations: nil, _meta: nil),
        ])
    }

    // MARK: - Locate

    private func runLocate(_ args: [String: Value]?) async throws -> CallTool.Result {
        let displayID = args?["displayID"]?.intValue.map { UInt32($0) } ?? CGMainDisplayID()
        let shot = try await capture.performCapture(
            CaptureRequest(mode: .display, displayID: displayID, format: .png), persist: false
        )
        let query = LocatorQuery(text: args?["text"]?.stringValue)
        let matches = try await locator.locate(query, inScreenshotPNG: shot.image.data)
        return try json(matches)
    }

    // MARK: - OCR

    private func runOCR(_ args: [String: Value]?) async throws -> CallTool.Result {
        let displayID = args?["displayID"]?.intValue.map { UInt32($0) } ?? CGMainDisplayID()
        let request: CaptureRequest
        if let rect = args?["rect"]?.objectValue {
            func value(_ key: String) -> CGFloat { CGFloat(rect[key]?.doubleValue ?? Double(rect[key]?.intValue ?? 0)) }
            request = CaptureRequest(
                mode: .region, displayID: displayID,
                rect: CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height")),
                format: .png
            )
        } else {
            request = CaptureRequest(mode: .display, displayID: displayID, format: .png)
        }
        let shot = try await capture.performCapture(request, persist: false)
        let text = try await recognizer.recognizeText(in: shot.image.data)
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    // MARK: - Privileged (gated)

    private func runPrivileged(_ tool: MCPTool, _ args: [String: Value]?) async throws -> CallTool.Result {
        let summary = Self.privilegedSummary(tool, args)
        guard await confirmInput(tool, summary) else {
            return Self.error("denied: \(tool.rawValue) requires user confirmation (\(summary))")
        }
        switch tool {
        case .switchApp:
            guard let bundle = args?["bundleID"]?.stringValue else {
                throw AIShotError.invalidRequest("switch_app requires bundleID")
            }
            try await automation.activate(bundleID: bundle)
            return Self.ok("activated \(bundle)")
        case .click:
            guard let x = number(args, "x"), let y = number(args, "y") else {
                throw AIShotError.invalidRequest("click requires x and y")
            }
            let button = MouseButton(rawValue: args?["button"]?.stringValue ?? "left") ?? .left
            try await automation.click(at: CGPoint(x: x, y: y), button: button)
            return Self.ok("clicked at (\(Int(x)), \(Int(y)))")
        case .typeText:
            guard let text = args?["text"]?.stringValue else {
                throw AIShotError.invalidRequest("type_text requires text")
            }
            try await automation.type(text: text)
            return Self.ok("typed \(text.count) characters")
        default:
            return Self.error("not a privileged tool: \(tool.rawValue)")
        }
    }

    private func number(_ args: [String: Value]?, _ key: String) -> CGFloat? {
        if let d = args?[key]?.doubleValue { return CGFloat(d) }
        if let i = args?[key]?.intValue { return CGFloat(i) }
        return nil
    }

    private static func privilegedSummary(_ tool: MCPTool, _ args: [String: Value]?) -> String {
        switch tool {
        case .switchApp: "switch to \(args?["bundleID"]?.stringValue ?? "?")"
        case .click: "click at (\(args?["x"]?.doubleValue ?? 0), \(args?["y"]?.doubleValue ?? 0))"
        case .typeText: "type \"\(args?["text"]?.stringValue ?? "")\""
        default: tool.rawValue
        }
    }

    // MARK: - Encoding helpers

    private func json<T: Encodable>(_ value: T) throws -> CallTool.Result {
        let data = try JSONEncoder().encode(value)
        return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
    }

    private static func jsonString(_ value: Value) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func error(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }

    private static func ok(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
    }
}
