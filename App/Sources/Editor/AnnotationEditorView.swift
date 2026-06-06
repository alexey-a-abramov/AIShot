import AppKit
import CoreGraphics
import SwiftUI
import AIShotAnnotation

/// Window host: builds an `EditorModel` from the app's pending editor image.
struct AnnotationEditorHost: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        if let data = app.editorImageData, app.editorPixelSize.width > 0 {
            AnnotationEditorView(editor: EditorModel(imageData: data, pixelSize: app.editorPixelSize))
                .environmentObject(app)
                .id(data.count)
        } else {
            ContentUnavailableView(
                "Nothing to edit",
                systemImage: "pencil.slash",
                description: Text("Capture a screenshot, then choose “Edit Last Capture”.")
            )
            .frame(minWidth: 460, minHeight: 320)
        }
    }
}

/// Interactive annotation editor: a toolbar plus a drag-to-draw canvas over the
/// captured image.
struct AnnotationEditorView: View {
    @StateObject var editor: EditorModel
    @EnvironmentObject private var app: AppModel
    @State private var nsImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { nsImage = NSImage(data: editor.imageData) }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $editor.tool) {
                ForEach(AnnotationTool.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .labelsHidden()
            .frame(width: 140)

            ColorPicker("", selection: Binding(
                get: { Color(editor.color) },
                set: { editor.color = RGBAColor($0) }
            ))
            .labelsHidden()

            Slider(value: $editor.lineWidth, in: 1...24).frame(width: 110)

            if editor.tool == .text || editor.tool == .counter {
                TextField("Text", text: $editor.textInput).frame(width: 120)
            }

            Spacer()

            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!editor.canUndo)
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!editor.canRedo)
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
        let width = annotation.lineWidth * fit.width / max(editor.pixelSize.width, 1)
        func viewPoint(_ index: Int) -> CGPoint {
            toViewSpace(annotation.points[min(index, annotation.points.count - 1)], fit: fit)
        }
        let box = CGRect(origin: viewPoint(0), size: .zero).union(CGRect(origin: viewPoint(1), size: .zero))

        switch annotation.tool {
        case .line, .arrow:
            var path = Path()
            path.move(to: viewPoint(0))
            path.addLine(to: viewPoint(1))
            context.stroke(path, with: .color(color), lineWidth: width)
        case .rectangle:
            context.stroke(Path(box), with: .color(color), lineWidth: width)
        case .ellipse:
            context.stroke(Path(ellipseIn: box), with: .color(color), lineWidth: width)
        case .highlighter:
            context.fill(Path(box), with: .color(color.opacity(0.3)))
        case .blur, .pixelate:
            context.fill(Path(box), with: .color(.gray.opacity(0.6)))
        case .text:
            context.draw(Text(annotation.text ?? "").foregroundColor(color), at: viewPoint(0), anchor: .topLeading)
        case .counter:
            let center = viewPoint(0)
            let radius: CGFloat = 12
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color)
            )
        }
    }
}
