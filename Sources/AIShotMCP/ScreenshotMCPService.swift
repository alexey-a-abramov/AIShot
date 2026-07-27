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
    private let redactor: AutoRedactor
    private let confirmInput: InputConfirmation
    /// Optional: when present, `search_captures` can match the text *inside*
    /// past captures, not just their notes/tags/file names.
    private let textIndexer: TextIndexer?
    private let metadataStore = CaptureMetadataStore()

    public init(
        capture: CaptureService,
        automation: AutomationEngine = AutomationEngine(),
        locator: any ElementLocating = VisionElementLocator(),
        renderer: any AnnotationRendering = CoreImageAnnotationRenderer(),
        recognizer: TextRecognizer = TextRecognizer(),
        redactor: AutoRedactor = AutoRedactor(),
        textIndexer: TextIndexer? = nil,
        confirmInput: @escaping InputConfirmation = { _, _ in false }
    ) {
        self.capture = capture
        self.automation = automation
        self.locator = locator
        self.renderer = renderer
        self.recognizer = recognizer
        self.redactor = redactor
        self.textIndexer = textIndexer
        self.confirmInput = confirmInput
    }

    /// Tool definitions advertised to agents.
    public nonisolated func toolDefinitions() -> [Tool] {
        MCPTool.allCases.map {
            Tool(name: $0.rawValue, description: $0.summary, inputSchema: ToolSchemas.schema(for: $0))
        }
    }

    // MARK: - Resources (capture history)

    /// Recent captures, exposed as MCP resources (`aishot://history/<uuid>`).
    public func resourceList() async -> [Resource] {
        let entries = (try? await capture.recentHistory(limit: 50)) ?? []
        return entries.compactMap { entry in
            guard let url = entry.fileURL else { return nil }
            return Resource(
                name: url.lastPathComponent,
                uri: "aishot://history/\(entry.id.uuidString)",
                description: "Capture \(entry.pixelWidth)×\(entry.pixelHeight)",
                mimeType: Self.mimeType(for: url)
            )
        }
    }

    /// Reads a history resource by URI, returning the file bytes.
    public func readResource(uri: String) async -> ReadResource.Result {
        let id = uri.split(separator: "/").last.map(String.init)
        let entries = (try? await capture.recentHistory(limit: 200)) ?? []
        if let id, let entry = entries.first(where: { $0.id.uuidString == id }),
           let url = entry.fileURL, let data = try? Data(contentsOf: url) {
            return ReadResource.Result(
                contents: [.binary(data, uri: uri, mimeType: Self.mimeType(for: url))]
            )
        }
        return ReadResource.Result(contents: [.text("resource not found: \(uri)", uri: uri)])
    }

    /// History holds screenshots *and* screen recordings, so the type has to be
    /// derived per file rather than assumed to be PNG.
    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "heic": "image/heic"
        case "tiff", "tif": "image/tiff"
        case "gif": "image/gif"
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        default: "application/octet-stream"
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
            case .searchCaptures: return try await searchCaptures(arguments)
            case .captureRegion: return try await runCapture(regionRequest(arguments))
            case .captureWindow: return try await runCapture(windowRequest(arguments))
            case .captureDisplay: return try await runCapture(displayRequest(arguments))
            case .annotate: return try await runAnnotate(arguments)
            case .beautify: return try await runBeautify(arguments)
            case .redact: return try await runRedact(arguments)
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
        let base = try Self.loadImage(args, tool: "annotate")
        let document = try AnnotationDecoding.document(from: args?["annotations"], basePNG: base)
        let rendered = try await renderer.render(document, onto: base)
        return Self.imageResult(rendered)
    }

    private func runBeautify(_ args: [String: Value]?) async throws -> CallTool.Result {
        let base = try Self.loadImage(args, tool: "beautify")
        return Self.imageResult(try Beautifier.beautify(base))
    }

    private func runRedact(_ args: [String: Value]?) async throws -> CallTool.Result {
        let base = try Self.loadImage(args, tool: "redact")
        return Self.imageResult(try await redactor.redact(in: base))
    }

    private static func loadImage(_ args: [String: Value]?, tool: String) throws -> Data {
        if let b64 = args?["imageBase64"]?.stringValue, let data = Data(base64Encoded: b64) {
            return data
        }
        if let path = args?["imagePath"]?.stringValue {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        }
        throw AIShotError.invalidRequest("\(tool) requires imageBase64 or imagePath")
    }

    private static func imageResult(_ png: Data) -> CallTool.Result {
        CallTool.Result(content: [
            .image(data: png.base64EncodedString(), mimeType: ImageFormat.png.mimeType, annotations: nil, _meta: nil),
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

    /// Finds past captures by the text inside them, plus note/tag/file name.
    ///
    /// One index, two consumers: the same OCR data backs the Dashboard's search
    /// box and this tool, so an agent can find "the screenshot with the stack
    /// trace" instead of only listing the most recent ones.
    private func searchCaptures(_ args: [String: Value]?) async throws -> CallTool.Result {
        let query = (args?["query"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Self.error("search_captures: 'query' is required") }
        // Bounded so an agent can't inline the whole index into one result.
        let limit = min(100, max(1, args?["limit"]?.intValue ?? 20))

        let entries = (try? await capture.recentHistory(limit: 500)) ?? []
        let textHits = await textIndexer?.search(query) ?? []
        let snippets = Dictionary(
            textHits.map { ($0.fileURL.standardizedFileURL, $0.snippet) },
            uniquingKeysWith: { first, _ in first }
        )

        var results: [SearchResult] = []
        var seen = Set<URL>()
        for entry in entries {
            guard let url = entry.fileURL?.standardizedFileURL else { continue }
            let meta = await metadata(for: url)
            let matchedText = snippets[url]
            let matchedNote = meta?.note.localizedCaseInsensitiveContains(query) ?? false
            let matchedTag = meta?.tag?.localizedCaseInsensitiveContains(query) ?? false
            let matchedName = url.lastPathComponent.localizedCaseInsensitiveContains(query)
            guard matchedText != nil || matchedNote || matchedTag || matchedName else { continue }
            guard seen.insert(url).inserted else { continue }
            results.append(SearchResult(
                path: url.path,
                createdAt: entry.createdAt,
                width: entry.pixelWidth,
                height: entry.pixelHeight,
                matchedOn: matchedText != nil ? "text"
                    : matchedNote ? "note"
                    : matchedTag ? "tag" : "filename",
                note: meta?.note.isEmpty == false ? meta?.note : nil,
                tag: meta?.tag,
                snippet: matchedText
            ))
            if results.count >= limit { break }
        }

        // Indexed captures that predate the history window still count.
        if results.count < limit {
            for hit in textHits {
                let url = hit.fileURL.standardizedFileURL
                guard seen.insert(url).inserted,
                      FileManager.default.fileExists(atPath: url.path) else { continue }
                results.append(SearchResult(
                    path: url.path, createdAt: nil, width: 0, height: 0,
                    matchedOn: "text", note: nil, tag: nil, snippet: hit.snippet
                ))
                if results.count >= limit { break }
            }
        }

        return try json(results)
    }

    /// Note/tag for a capture, resolved through the same per-directory index
    /// the app writes (hidden dotfile beside the image, or the visible one).
    private func metadata(for fileURL: URL) async -> CaptureMetadata? {
        let directory = fileURL.deletingLastPathComponent()
        for name in [CaptureMetadataStore.hiddenFileName, CaptureMetadataStore.visibleFileName] {
            let indexURL = directory.appendingPathComponent(name)
            if let meta = await metadataStore.metadata(at: indexURL, key: fileURL.lastPathComponent) {
                return meta
            }
        }
        return nil
    }

    /// Agent-facing shape of a `search_captures` result.
    private struct SearchResult: Encodable {
        var path: String
        var createdAt: Date?
        var width: Int
        var height: Int
        /// Which field matched: "text" (words inside the image), "note", "tag",
        /// or "filename".
        var matchedOn: String
        var note: String?
        var tag: String?
        var snippet: String?
    }

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
