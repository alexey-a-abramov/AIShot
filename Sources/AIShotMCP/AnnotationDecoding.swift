import CoreGraphics
import Foundation
import MCP
import AIShotAnnotation
import AIShotCapture

/// Decodes the `annotations` MCP argument (a JSON array as `Value`) into an
/// `AnnotationDocument`, sizing it from the decoded base image.
enum AnnotationDecoding {
    static func document(from value: Value?, basePNG: Data) throws -> AnnotationDocument {
        let image = try ImageCodec.decode(basePNG)
        let size = CGSize(width: image.width, height: image.height)
        let annotations = (value?.arrayValue ?? []).compactMap(decode)
        return AnnotationDocument(baseImageSize: size, annotations: annotations)
    }

    private static func decode(_ value: Value) -> Annotation? {
        guard let object = value.objectValue,
              let toolName = object["tool"]?.stringValue,
              let tool = AnnotationTool(rawValue: toolName) else { return nil }
        let points = (object["points"]?.arrayValue ?? []).compactMap { point -> CGPoint? in
            guard let p = point.objectValue else { return nil }
            return CGPoint(x: number(p["x"]), y: number(p["y"]))
        }
        let color = decodeColor(object["color"]) ?? .red
        let width = object["lineWidth"]?.doubleValue ?? Double(object["lineWidth"]?.intValue ?? 3)
        return Annotation(
            tool: tool,
            points: points,
            color: color,
            lineWidth: width,
            text: object["text"]?.stringValue,
            fontSize: object["fontSize"]?.doubleValue
        )
    }

    private static func decodeColor(_ value: Value?) -> RGBAColor? {
        guard let object = value?.objectValue else { return nil }
        return RGBAColor(
            r: number(object["r"]),
            g: number(object["g"]),
            b: number(object["b"]),
            a: number(object["a"] ?? .double(1))
        )
    }

    private static func number(_ value: Value?) -> Double {
        value?.doubleValue ?? Double(value?.intValue ?? 0)
    }
}
