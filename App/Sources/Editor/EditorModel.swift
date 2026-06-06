import CoreGraphics
import Foundation
import SwiftUI
import AIShotAnnotation

/// State for the annotation editor: the base image, committed + in-progress
/// annotations, current tool/color, and undo/redo. Coordinates are in the base
/// image's pixel space.
@MainActor
final class EditorModel: ObservableObject {
    @Published var annotations: [Annotation] = []
    @Published var draft: Annotation?
    @Published var tool: AnnotationTool = .arrow
    @Published var color: RGBAColor = .red
    @Published var lineWidth: Double = 4
    @Published var textInput: String = "Label"

    let imageData: Data
    let pixelSize: CGSize
    private var redoStack: [Annotation] = []
    private let renderer = CoreImageAnnotationRenderer()

    init(imageData: Data, pixelSize: CGSize) {
        self.imageData = imageData
        self.pixelSize = pixelSize
    }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func begin(at point: CGPoint) {
        draft = Annotation(
            tool: tool,
            points: [point, point],
            color: color,
            lineWidth: lineWidth,
            text: (tool == .text || tool == .counter) ? textInput : nil,
            fontSize: tool == .text ? max(12, lineWidth * 5) : nil
        )
    }

    func extend(to point: CGPoint) {
        guard var current = draft else { return }
        let start = current.points.first ?? point
        current.points = [start, point]
        draft = current
    }

    func commit() {
        guard let draft else { return }
        annotations.append(draft)
        self.draft = nil
        redoStack.removeAll()
    }

    func undo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        annotations.append(entry)
    }

    func document() -> AnnotationDocument {
        AnnotationDocument(baseImageSize: pixelSize, annotations: annotations)
    }

    /// Flattens the annotations onto the base image, returning PNG bytes.
    func flatten() async -> Data? {
        try? await renderer.render(document(), onto: imageData)
    }
}
