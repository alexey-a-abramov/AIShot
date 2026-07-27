import Foundation
import AIShotCore
import AIShotPersistence

extension CaptureMode {
    /// Localized display name. Reuses the strings already used by the capture
    /// actions in the menu bar and dashboard sidebar, so a badge on a card and
    /// the button that produced it read the same.
    var displayName: String {
        switch self {
        case .region: String(localized: "Region")
        case .window: String(localized: "Window")
        case .display: String(localized: "Full Screen")
        case .allDisplays: String(localized: "All Displays")
        }
    }

    /// Matches the SF Symbols used by the sidebar capture buttons.
    var iconName: String {
        switch self {
        case .region: "viewfinder"
        case .window: "macwindow"
        case .display: "display"
        case .allDisplays: "rectangle.on.rectangle"
        }
    }
}

extension CaptureKind {
    var iconName: String {
        switch self {
        case .image: "photo"
        case .video: "video"
        }
    }
}
