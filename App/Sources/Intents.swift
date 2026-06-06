import AppIntents

/// Captures the main display via the Shortcuts app, Spotlight, or Siri.
struct CaptureScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Full Screen"
    static let description = IntentDescription("Captures the main display, saves it, and returns the file path.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let path = await AppModel.shared.captureFullScreenReturningPath() ?? ""
        return .result(value: path)
    }
}

/// Surfaces AIShot actions in Shortcuts and Spotlight.
struct AIShotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureScreenshotIntent(),
            phrases: ["Capture screen with \(.applicationName)"],
            shortTitle: "Capture Full Screen",
            systemImageName: "camera.viewfinder"
        )
    }
}
