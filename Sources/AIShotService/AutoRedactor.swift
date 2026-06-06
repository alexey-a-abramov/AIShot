import CoreGraphics
import Foundation
import AIShotAnnotation
import AIShotAutomation
import AIShotCore

/// Common patterns for sensitive data.
public enum SensitivePatterns {
    public static let email = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
    public static let creditCard = "\\b(?:\\d[ -]?){13,16}\\b"
    public static let ipAddress = "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b"
    public static let defaults = [email, creditCard, ipAddress]
}

public struct RedactionMatch: Sendable, Equatable {
    public let rect: CGRect
    public let text: String
}

/// Detects and blurs sensitive text in a screenshot (Xnapper-style auto-redact),
/// combining Vision OCR with regex matching and the annotation renderer.
public actor AutoRedactor {
    private let locator: any ElementLocating
    private let renderer: any AnnotationRendering

    public init(
        locator: any ElementLocating = VisionElementLocator(),
        renderer: any AnnotationRendering = CoreImageAnnotationRenderer()
    ) {
        self.locator = locator
        self.renderer = renderer
    }

    /// Whether `text` matches any of the patterns.
    public static func isSensitive(_ text: String, patterns: [String] = SensitivePatterns.defaults) -> Bool {
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        let range = NSRange(text.startIndex..., in: text)
        return regexes.contains { $0.firstMatch(in: text, options: [], range: range) != nil }
    }

    /// OCRs the image and returns regions whose recognized text is sensitive.
    public func detect(in png: Data, patterns: [String] = SensitivePatterns.defaults) async throws -> [RedactionMatch] {
        let found = try await locator.locate(LocatorQuery(), inScreenshotPNG: png)
        return found.compactMap { match in
            guard let text = match.text, Self.isSensitive(text, patterns: patterns) else { return nil }
            return RedactionMatch(rect: match.rect, text: text)
        }
    }

    /// Returns the image with sensitive regions blurred (or the original if none).
    public func redact(in png: Data, patterns: [String] = SensitivePatterns.defaults) async throws -> Data {
        let matches = try await detect(in: png, patterns: patterns)
        guard !matches.isEmpty else { return png }
        let annotations = matches.map {
            Annotation(
                tool: .blur,
                points: [$0.rect.origin, CGPoint(x: $0.rect.maxX, y: $0.rect.maxY)]
            )
        }
        let document = AnnotationDocument(baseImageSize: .zero, annotations: annotations)
        return try await renderer.render(document, onto: png)
    }
}
