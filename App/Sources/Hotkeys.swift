import KeyboardShortcuts

/// User-customizable global hotkeys. Defaults use ⌘⌥⇧ to avoid clashing with
/// the system screenshot shortcuts (⌘⇧3/4/5). Every action is reassignable in
/// Settings → Shortcuts (and can be cleared).
extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion", default: .init(.four, modifiers: [.command, .option, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.five, modifiers: [.command, .option, .shift]))
    static let captureFullScreen = Self("captureFullScreen", default: .init(.three, modifiers: [.command, .option, .shift]))
    static let captureAllDisplays = Self("captureAllDisplays", default: .init(.two, modifiers: [.command, .option, .shift]))
    static let captureText = Self("captureText", default: .init(.t, modifiers: [.command, .option, .shift]))
    static let scrollingCapture = Self("scrollingCapture", default: .init(.l, modifiers: [.command, .option, .shift]))
    static let pickColor = Self("pickColor", default: .init(.c, modifiers: [.command, .option, .shift]))
    static let pinLastCapture = Self("pinLastCapture", default: .init(.p, modifiers: [.command, .option, .shift]))
    static let editLastCapture = Self("editLastCapture", default: .init(.e, modifiers: [.command, .option, .shift]))
    static let toggleRecording = Self("toggleRecording", default: .init(.r, modifiers: [.command, .option, .shift]))
}
