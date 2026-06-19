import CoreGraphics
import Foundation
import SwiftUI
import AIShotAnnotation
import AIShotCapture
import AIShotService

/// Editor interaction mode: pointer (select/move) or a drawing tool.
enum EditorMode: Equatable, Hashable {
    case select
    case draw(AnnotationTool)
}

/// State for the vector annotation editor. Annotations stay editable objects
/// (selectable, movable, restylable) until the image is flattened on Copy/Save.
@MainActor
final class EditorModel: ObservableObject {
    @Published var annotations: [Annotation] = []
    @Published var draft: Annotation?
    @Published var mode: EditorMode = .select {
        didSet { if mode != oldValue { endTextEditing() } }
    }
    /// Default style for NEW objects (also edited when nothing is selected).
    @Published var color: RGBAColor = .red
    @Published var lineWidth: Double = 4
    @Published var selectedID: UUID?
    @Published var editingTextID: UUID?
    @Published private(set) var imageData: Data
    @Published private(set) var pixelSize: CGSize

    /// Snapshot-based undo: each entry is a full annotation list before an edit.
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    /// Coalescing key so a continuous edit (a drag or slider sweep) pushes one
    /// undo step, not hundreds.
    private var lastUndoKey: String?

    private let renderer = CoreImageAnnotationRenderer()
    private let redactor = AutoRedactor()

    init(imageData: Data, pixelSize: CGSize) {
        self.imageData = imageData
        self.pixelSize = pixelSize
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasSelection: Bool { selectedID != nil }
    var isEditingText: Bool { editingTextID != nil }

    // MARK: - Undo

    private func pushUndo(_ key: String? = nil) {
        if let key, key == lastUndoKey { return } // same continuous edit
        undoStack.append(annotations)
        redoStack.removeAll()
        lastUndoKey = key
    }

    /// Ends a continuous edit so the next one starts a fresh undo step.
    func endEditCoalescing() { lastUndoKey = nil }

    func undo() {
        endTextEditing()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedID = nil
        editingTextID = nil
        lastUndoKey = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedID = nil
        editingTextID = nil
        lastUndoKey = nil
    }

    // MARK: - Drawing (drag tools)

    func begin(_ tool: AnnotationTool, at point: CGPoint) {
        endTextEditing()
        draft = Annotation(tool: tool, points: [point, point], color: color, lineWidth: lineWidth)
    }

    func extend(to point: CGPoint) {
        guard var current = draft else { return }
        current.points = [current.points.first ?? point, point]
        draft = current
    }

    func commit() {
        guard let draft else { return }
        pushUndo()
        annotations.append(draft)
        self.draft = nil
        selectedID = draft.id
    }

    // MARK: - Inline text

    func beginText(at point: CGPoint) {
        endTextEditing()
        pushUndo()
        let annotation = Annotation(
            tool: .text, points: [point], color: color, lineWidth: lineWidth,
            text: "", fontSize: max(12, lineWidth * 5)
        )
        annotations.append(annotation)
        selectedID = annotation.id
        editingTextID = annotation.id
    }

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

    func endTextEditing() {
        if let id = editingTextID,
           let index = annotations.firstIndex(where: { $0.id == id }),
           (annotations[index].text ?? "").isEmpty {
            annotations.remove(at: index)
            if selectedID == id { selectedID = nil }
        }
        editingTextID = nil
    }

    // MARK: - Selection & manipulation

    func selectIfHit(at point: CGPoint) {
        selectedID = hitTest(point)
    }

    /// A tap (no drag): select, re-edit text if tapping an already-selected
    /// label, or deselect when tapping empty space.
    func handleTap(at point: CGPoint) {
        let hit = hitTest(point)
        if hit == nil { selectedID = nil; return }
        if hit == selectedID, annotations.first(where: { $0.id == hit })?.tool == .text {
            editingTextID = hit
            return
        }
        selectedID = hit
    }

    func moveSelected(by delta: CGSize) {
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        pushUndo("move")
        annotations[index].points = annotations[index].points.map {
            CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
        }
    }

    func deleteSelected() {
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        annotations.remove(at: index)
        if editingTextID == id { editingTextID = nil }
        selectedID = nil
    }

    func hitTest(_ point: CGPoint) -> UUID? {
        for annotation in annotations.reversed() where hitBox(annotation).contains(point) {
            return annotation.id
        }
        return nil
    }

    private func hitBox(_ annotation: Annotation) -> CGRect {
        switch annotation.tool {
        case .text:
            let origin = annotation.points.first ?? .zero
            let size = CGFloat(annotation.fontSize ?? 18)
            let width = max(40, CGFloat((annotation.text ?? "").count) * size * 0.6)
            return CGRect(x: origin.x, y: origin.y, width: width, height: size * 1.4)
        case .counter:
            let center = annotation.points.first ?? .zero
            let radius = max(10, CGFloat(annotation.lineWidth) * 5)
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        default:
            let pad = max(8, CGFloat(annotation.lineWidth))
            return annotation.boundingBox.insetBy(dx: -pad, dy: -pad)
        }
    }

    var selectionBox: CGRect? {
        guard let id = selectedID, let annotation = annotations.first(where: { $0.id == id }) else { return nil }
        return hitBox(annotation)
    }

    // MARK: - Style bindings (apply to the selection, else to new-object defaults)

    var colorBinding: Binding<Color> {
        Binding(
            get: { [weak self] in
                guard let self else { return .red }
                if let id = self.selectedID, let annotation = self.annotations.first(where: { $0.id == id }) {
                    return Color(annotation.color)
                }
                return Color(self.color)
            },
            set: { [weak self] newColor in
                guard let self else { return }
                let rgba = RGBAColor(newColor)
                if let id = self.selectedID, let index = self.annotations.firstIndex(where: { $0.id == id }) {
                    self.pushUndo("color")
                    self.annotations[index].color = rgba
                } else {
                    self.color = rgba
                }
            }
        )
    }

    /// Stroke thickness for shapes, or font size for a selected text label.
    var sizeBinding: Binding<Double> {
        Binding(
            get: { [weak self] in
                guard let self else { return 4 }
                if let id = self.selectedID, let annotation = self.annotations.first(where: { $0.id == id }) {
                    return annotation.tool == .text ? (annotation.fontSize ?? 18) : annotation.lineWidth
                }
                return self.lineWidth
            },
            set: { [weak self] value in
                guard let self else { return }
                if let id = self.selectedID, let index = self.annotations.firstIndex(where: { $0.id == id }) {
                    self.pushUndo("size")
                    if self.annotations[index].tool == .text {
                        self.annotations[index].fontSize = value
                    } else {
                        self.annotations[index].lineWidth = value
                    }
                } else {
                    self.lineWidth = value
                }
            }
        )
    }

    // MARK: - Image operations

    func document() -> AnnotationDocument {
        AnnotationDocument(baseImageSize: pixelSize, annotations: annotations)
    }

    func flatten() async -> Data? {
        endTextEditing()
        return try? await renderer.render(document(), onto: imageData)
    }

    /// Bakes annotations in and frames the image on a gradient background.
    func applyBeautify() async {
        guard let flat = await flatten(), let out = try? Beautifier.beautify(flat) else { return }
        setImage(out)
    }

    /// Bakes annotations in and blurs auto-detected sensitive text.
    func applyRedact() async {
        guard let flat = await flatten(), let out = try? await redactor.redact(in: flat) else { return }
        setImage(out)
    }

    private func setImage(_ data: Data) {
        imageData = data
        if let cgImage = try? ImageCodec.decode(data) {
            pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        }
        annotations = []
        draft = nil
        undoStack.removeAll()
        redoStack.removeAll()
        lastUndoKey = nil
        selectedID = nil
        editingTextID = nil
    }
}
