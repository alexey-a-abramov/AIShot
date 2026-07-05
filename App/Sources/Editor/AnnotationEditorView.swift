import AppKit
import CoreGraphics
import SwiftUI
import AIShotAnnotation

/// Vector annotation editor: pick the pointer to select/move/restyle objects, or
/// a drawing tool to add them. Objects stay editable until Copy/Save flattens.
struct AnnotationEditorView: View {
    @StateObject var editor: EditorModel
    @EnvironmentObject private var app: AppModel
    @State private var nsImage: NSImage?
    @State private var dragStart: CGPoint?
    @State private var lastPoint: CGPoint = .zero
    @State private var dragMoved = false
    @FocusState private var textFieldFocused: Bool

    /// Drawing tools: (tool, SF Symbol, tooltip).
    private static let drawTools: [(AnnotationTool, String, String)] = [
        (.arrow, "arrow.up.right", "Arrow"),
        (.line, "line.diagonal", "Line"),
        (.rectangle, "rectangle", "Rectangle"),
        (.ellipse, "circle", "Ellipse"),
        (.text, "textformat", "Text label"),
        (.counter, "number.circle", "Numbered step"),
        (.highlighter, "highlighter", "Highlighter"),
        (.blur, "drop.fill", "Blur — obscure an area"),
        (.pixelate, "squareshape.split.3x3", "Pixelate — obscure an area"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
        .frame(minWidth: 820, minHeight: 480)
        .onAppear { nsImage = NSImage(data: editor.imageData) }
        .onChange(of: editor.imageData) { _, data in nsImage = NSImage(data: data) }
        // Esc: cancel a text edit, discard an in-progress draft, deselect,
        // then fall back to switching back to the pointer tool.
        .onKeyPress(.escape) {
            editor.handleEscape()
            return .handled
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                paletteButton(.select, "cursorarrow", "Select / Move")
                ForEach(Self.drawTools, id: \.0) { tool, icon, help in
                    paletteButton(.draw(tool), icon, help)
                }
            }
            Text(modeName).font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)

            Divider().frame(height: 20)

            ColorPicker("", selection: editor.colorBinding).labelsHidden().help("Color")
            Slider(value: editor.sizeBinding, in: 1...40, onEditingChanged: { editing in
                if !editing { editor.endEditCoalescing() }
            })
            .frame(width: 84).help("Size / thickness")
            Button { editor.deleteSelected() } label: { Image(systemName: "trash") }
                .disabled(!editor.hasSelection || editor.isEditingText).help("Delete selected (⌫)")
                .keyboardShortcut(.delete, modifiers: [])

            Spacer()

            Button("Beautify") { Task { await editor.applyBeautify() } }
                .help("Frame on a gradient background")
            Button("Redact") { Task { await editor.applyRedact() } }
                .help("Blur auto-detected emails / cards / IPs")

            Divider().frame(height: 20)

            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!editor.canUndo).keyboardShortcut("z", modifiers: .command).help("Undo (⌘Z)")
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!editor.canRedo).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo (⇧⌘Z)")
            Button("Copy") { export(copy: true, save: false) }
            Button("Save") { export(copy: false, save: true) }
                .keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
        }
        .padding(8)
    }

    private func paletteButton(_ buttonMode: EditorMode, _ icon: String, _ help: String) -> some View {
        Button { editor.mode = buttonMode } label: {
            Image(systemName: icon).frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .background(
            editor.mode == buttonMode ? Color.accentColor.opacity(0.28) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .help(help)
    }

    private var modeName: String {
        switch editor.mode {
        case .select: "Select"
        case .draw(let tool): tool.rawValue.capitalized
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let fit = fittedRect(image: editor.pixelSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                if let nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                }
                Canvas { context, _ in
                    let items = (editor.annotations + (editor.draft.map { [$0] } ?? []))
                        .filter { $0.id != editor.editingTextID }
                    for item in items { drawPreview(item, in: &context, fit: fit) }
                    drawSelection(in: &context, fit: fit)
                }
                .allowsHitTesting(false)

                inlineTextEditor(fit: fit)
            }
            .contentShape(Rectangle())
            .gesture(canvasGesture(fit: fit))
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: editor.editingTextID) { _, id in textFieldFocused = (id != nil) }
        }
    }

    private func canvasGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = toImageSpace(value.location, fit: fit)
                switch editor.mode {
                case .select:
                    if dragStart == nil {
                        dragStart = point
                        lastPoint = point
                        dragMoved = false
                        editor.selectIfHit(at: point)
                    } else {
                        let dx = point.x - lastPoint.x
                        let dy = point.y - lastPoint.y
                        if abs(dx) + abs(dy) > 0.5 {
                            dragMoved = true
                            editor.moveSelected(by: CGSize(width: dx, height: dy))
                            lastPoint = point
                        }
                    }
                case .draw(let tool):
                    guard tool != .text else { return }
                    if editor.draft == nil { editor.begin(tool, at: point) } else { editor.extend(to: point) }
                }
            }
            .onEnded { value in
                let point = toImageSpace(value.location, fit: fit)
                switch editor.mode {
                case .select:
                    if !dragMoved { editor.handleTap(at: point) }
                    dragStart = nil
                    dragMoved = false
                case .draw(let tool):
                    if tool == .text { editor.beginText(at: point) } else { editor.commit() }
                }
                editor.endEditCoalescing()
            }
    }

    @ViewBuilder
    private func inlineTextEditor(fit: CGRect) -> some View {
        if let id = editor.editingTextID,
           let annotation = editor.annotations.first(where: { $0.id == id }) {
            let pos = toViewSpace(annotation.points[0], fit: fit)
            let fontPx = max(12, (annotation.fontSize ?? 18) * fit.width / max(editor.pixelSize.width, 1))
            TextField("Type label…", text: editor.textBinding())
                .textFieldStyle(.plain)
                .font(.system(size: fontPx, weight: .semibold))
                .foregroundStyle(Color(annotation.color))
                .frame(width: 240)
                .padding(3)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                .focused($textFieldFocused)
                .offset(x: pos.x, y: pos.y)
                .onSubmit { editor.endTextEditing() }
        }
    }

    private func export(copy: Bool, save: Bool) {
        Task {
            if let data = await editor.flatten() {
                await app.export(data, copy: copy, save: save)
            }
        }
    }

    // MARK: - Coordinate mapping

    private func fittedRect(image: CGSize, in container: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }

    private func toImageSpace(_ point: CGPoint, fit: CGRect) -> CGPoint {
        guard fit.width > 0, fit.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - fit.minX) * editor.pixelSize.width / fit.width,
            y: (point.y - fit.minY) * editor.pixelSize.height / fit.height
        )
    }

    private func toViewSpace(_ point: CGPoint, fit: CGRect) -> CGPoint {
        CGPoint(
            x: fit.minX + point.x * fit.width / max(editor.pixelSize.width, 1),
            y: fit.minY + point.y * fit.height / max(editor.pixelSize.height, 1)
        )
    }

    private func drawSelection(in context: inout GraphicsContext, fit: CGRect) {
        guard let box = editor.selectionBox else { return }
        let topLeft = toViewSpace(CGPoint(x: box.minX, y: box.minY), fit: fit)
        let bottomRight = toViewSpace(CGPoint(x: box.maxX, y: box.maxY), fit: fit)
        let rect = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        context.stroke(
            Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerSize: CGSize(width: 4, height: 4)),
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )
    }

    private func drawPreview(_ annotation: Annotation, in context: inout GraphicsContext, fit: CGRect) {
        guard !annotation.points.isEmpty else { return }
        let color = Color(annotation.color)
        let width = max(1, annotation.lineWidth * fit.width / max(editor.pixelSize.width, 1))
        func viewPoint(_ index: Int) -> CGPoint {
            toViewSpace(annotation.points[min(index, annotation.points.count - 1)], fit: fit)
        }
        let box = CGRect(origin: viewPoint(0), size: .zero).union(CGRect(origin: viewPoint(1), size: .zero))

        switch annotation.tool {
        case .line:
            var path = Path()
            path.move(to: viewPoint(0))
            path.addLine(to: viewPoint(1))
            context.stroke(path, with: .color(color), lineWidth: width)
        case .arrow:
            let from = viewPoint(0)
            let tip = viewPoint(1)
            var shaft = Path()
            shaft.move(to: from)
            shaft.addLine(to: tip)
            context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            let head = ArrowGeometry.arrowHead(from: from, tip: tip, length: max(10, width * 3.5))
            var triangle = Path()
            triangle.move(to: tip)
            triangle.addLine(to: head.left)
            triangle.addLine(to: head.right)
            triangle.closeSubpath()
            context.fill(triangle, with: .color(color))
        case .rectangle:
            context.stroke(Path(box), with: .color(color), lineWidth: width)
        case .ellipse:
            context.stroke(Path(ellipseIn: box), with: .color(color), lineWidth: width)
        case .highlighter:
            context.fill(Path(box), with: .color(color.opacity(0.3)))
        case .blur, .pixelate:
            context.fill(Path(box), with: .color(.gray.opacity(0.6)))
        case .text:
            context.draw(
                Text(annotation.text ?? "").font(.system(size: max(11, width * 5))).foregroundColor(color),
                at: viewPoint(0), anchor: .topLeading
            )
        case .counter:
            let center = viewPoint(0)
            let radius = max(10, width * 4)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color)
            )
            if let number = annotation.text, !number.isEmpty {
                context.draw(
                    Text(number).font(.system(size: radius * 1.05, weight: .bold))
                        .foregroundColor(Color(annotation.color.contrastingLabelColor)),
                    at: center, anchor: .center
                )
            }
        }
    }
}
