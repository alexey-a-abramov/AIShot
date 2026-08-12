import CoreGraphics
import Foundation
import AIShotAnnotation
import AIShotPersistence

/// What the user chose to do with a selection in the capture panel.
enum CapturePanelAction: Sendable, Equatable {
    case copy, save, saveAs, pin, ocr, openEditor

    /// The action the big default button performs, following the user's
    /// configured post-capture behaviour.
    static func primary(for action: PostCaptureAction) -> CapturePanelAction {
        switch action {
        case .copyToClipboard: .copy
        case .openEditor: .openEditor
        case .saveOnly: .save
        }
    }
}

/// Everything the overlay hands back when a capture completes.
struct CaptureSelectionResult: Sendable {
    /// Display and display-local, top-left rect in **points**.
    var selection: RegionSelection
    /// The same region as an integral rect in the frozen snapshot's **pixel**
    /// space, computed once so the crop and the annotation translation can
    /// never disagree by a pixel. `nil` when there is no snapshot.
    var pixelRect: CGRect?
    /// Annotations drawn on the panel, in that same snapshot pixel space.
    /// Translate by `pixelRect.origin` before rendering onto the crop.
    var annotations: [Annotation]
    /// `nil` when the overlay was only used to pick a region (OCR, scrolling).
    var action: CapturePanelAction?

    init(
        selection: RegionSelection,
        pixelRect: CGRect? = nil,
        annotations: [Annotation] = [],
        action: CapturePanelAction? = nil
    ) {
        self.selection = selection
        self.pixelRect = pixelRect
        self.annotations = annotations
        self.action = action
    }
}
