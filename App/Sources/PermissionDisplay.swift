import Foundation
import AIShotShared

extension Permission {
    /// Localized display name (resolved at runtime via the String Catalog).
    var displayName: String {
        switch self {
        case .screenRecording: String(localized: "Screen Recording")
        case .accessibility: String(localized: "Accessibility")
        case .notifications: String(localized: "Notifications")
        }
    }

    var iconName: String {
        switch self {
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        case .notifications: "bell"
        }
    }
}
