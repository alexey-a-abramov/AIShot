import SwiftUI
import AIShotAnnotation

/// Draws an in-progress annotation into a SwiftUI `Canvas`.
///
/// Shared by the editor window and the inline capture panel so the two can't
/// drift — an annotation must look the same wherever you draw it, and identical
/// to what the renderer finally bakes into the image.
enum AnnotationPreview {
    /// Maps a point from base-image pixel space into the fitted view rect.
    static func toViewSpace(_ point: CGPoint, fit: CGRect, pixelSize: CGSize) -> CGPoint {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return .zero }
        return CGPoint(
            x: fit.minX + point.x / pixelSize.width * fit.width,
            y: fit.minY + point.y / pixelSize.height * fit.height
        )
    }

    static func draw(
        _ annotation: Annotation,
        in context: inout GraphicsContext,
        fit: CGRect,
        pixelSize: CGSize
    ) {
        guard !annotation.points.isEmpty else { return }
        let color = Color(annotation.color)
        let width = max(1, annotation.lineWidth * fit.width / max(pixelSize.width, 1))
        func viewPoint(_ index: Int) -> CGPoint {
            AnnotationPreview.toViewSpace(annotation.points[min(index, annotation.points.count - 1)],
                                         fit: fit, pixelSize: pixelSize)
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
