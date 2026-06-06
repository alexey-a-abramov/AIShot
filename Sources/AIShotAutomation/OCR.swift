import CoreGraphics
import Foundation
import ImageIO
import Vision
import AIShotCore

/// Recognizes text in an image (text-grab / OCR), backed by Vision.
public actor TextRecognizer {
    public init() {}

    /// Recognized text lines, top to bottom.
    public func recognizeLines(in png: Data, languages: [String] = []) throws -> [String] {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIShotError.invalidRequest("ocr: undecodable image")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !languages.isEmpty { request.recognitionLanguages = languages }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// Recognized text as a single newline-joined string.
    public func recognizeText(in png: Data, languages: [String] = []) throws -> String {
        try recognizeLines(in: png, languages: languages).joined(separator: "\n")
    }
}
