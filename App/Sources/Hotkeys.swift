import KeyboardShortcuts

/// User-customizable global hotkeys. Defaults use ⌘⌥⇧ to avoid clashing with
/// the system screenshot shortcuts (⌘⇧3/4/5).
extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion", default: .init(.four, modifiers: [.command, .option, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.five, modifiers: [.command, .option, .shift]))
    static let captureFullScreen = Self("captureFullScreen", default: .init(.three, modifiers: [.command, .option, .shift]))
}
