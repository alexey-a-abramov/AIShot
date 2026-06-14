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
    @Published var tool: AnnotationTool = .arrow {
        didSet { if tool != oldValue { endTextEditing() } }
    }
    @Published var color: RGBAColor = .red
    @Published var lineWidth: Double = 4
    /// Identifier of the text annotation currently being edited inline (if any).
    @Published var editingTextID: UUID?

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

    // MARK: - Drawing (drag tools)

    func begin(at point: CGPoint) {
        endTextEditing()
        draft = Annotation(tool: tool, points: [point, point], color: color, lineWidth: lineWidth)
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

    // MARK: - Inline text

    /// Places an empty text annotation and starts editing it in place.
    /// Finalizes any previous in-progress label first, deterministically.
    func beginText(at point: CGPoint) {
        endTextEditing()
        let annotation = Annotation(
            tool: .text,
            points: [point],
            color: color,
            lineWidth: lineWidth,
            text: "",
            fontSize: max(12, lineWidth * 5)
        )
        annotations.append(annotation)
        redoStack.removeAll()
        editingTextID = annotation.id
    }

    /// Binding to the text of the annotation being edited.
    func textBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard let self, let id = self.editingTextID,
                      let annotation = self.annotations.first(where: { $0.id == id }) else { return "" }
                return annotation.text ?? ""
            },
            set: { [weak self] newValue in
                guard let self, let id = self.editingTextID,
                      let index = self.annotations.firstIndex(where: { $0.id == id }) else { return }
                self.annotations[index].text = newValue
            }
        )
    }

    /// Finishes inline editing, discarding the annotation if it's empty.
    func endTextEditing() {
        if let id = editingTextID,
           let index = annotations.firstIndex(where: { $0.id == id }),
           (annotations[index].text ?? "").isEmpty {
            annotations.remove(at: index)
        }
        editingTextID = nil
    }

    // MARK: - Undo / redo

    func undo() {
        endTextEditing()
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        endTextEditing()
        guard let entry = redoStack.popLast() else { return }
        annotations.append(entry)
    }

    func document() -> AnnotationDocument {
        AnnotationDocument(baseImageSize: pixelSize, annotations: annotations)
    }

    /// Flattens the annotations onto the base image, returning PNG bytes.
    func flatten() async -> Data? {
        endTextEditing()
        return try? await renderer.render(document(), onto: imageData)
    }
}
