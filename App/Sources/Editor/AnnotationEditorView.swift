import AppKit
import CoreGraphics
import SwiftUI
import AIShotAnnotation

/// Interactive annotation editor: an icon tool palette plus a drag-to-draw
/// canvas over the captured image.
struct AnnotationEditorView: View {
    @StateObject var editor: EditorModel
    @EnvironmentObject private var app: AppModel
    @State private var nsImage: NSImage?

    /// Tool palette: (tool, SF Symbol, tooltip).
    private static let palette: [(AnnotationTool, String, String)] = [
        (.arrow, "arrow.up.right", "Arrow"),
        (.line, "line.diagonal", "Line"),
        (.rectangle, "rectangle", "Rectangle"),
        (.ellipse, "circle", "Ellipse"),
        (.text, "textformat", "Text label"),
        (.counter, "number.circle", "Numbered step"),
        (.highlighter, "highlighter", "Highlighter"),
        (.blur, "drop.fill", "Blur"),
        (.pixelate, "squareshape.split.3x3", "Pixelate"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
        .frame(minWidth: 680, minHeight: 480)
        .onAppear { nsImage = NSImage(data: editor.imageData) }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Self.palette, id: \.0) { tool, icon, help in
                    Button { editor.tool = tool } label: {
                        Image(systemName: icon)
                            .frame(width: 26, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .background(
                        editor.tool == tool ? Color.accentColor.opacity(0.28) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .help(help)
                }
            }

            Divider().frame(height: 20)

            ColorPicker("", selection: Binding(
                get: { Color(editor.color) },
                set: { editor.color = RGBAColor($0) }
            ))
            .labelsHidden()
            .help("Color")

            Slider(value: $editor.lineWidth, in: 1...24).frame(width: 90).help("Thickness")

            if editor.tool == .text || editor.tool == .counter {
                TextField("Label", text: $editor.textInput).frame(width: 110)
            }

            Spacer()

            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!editor.canUndo).help("Undo")
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!editor.canRedo).help("Redo")
            Button("Copy") { export(copy: true, save: false) }
            Button("Save") { export(copy: false, save: true) }
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(8)
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
                    let items = editor.annotations + (editor.draft.map { [$0] } ?? [])
                    for item in items { drawPreview(item, in: &context, fit: fit) }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = toImageSpace(value.location, fit: fit)
                        if editor.draft == nil { editor.begin(at: point) } else { editor.extend(to: point) }
                    }
                    .onEnded { _ in editor.commit() }
            )
            .background(Color(nsColor: .windowBackgroundColor))
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
        }
    }
}
