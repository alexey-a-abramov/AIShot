import AIShotShared

extension Permission {
    var displayName: String {
        switch self {
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        case .notifications: "Notifications"
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
