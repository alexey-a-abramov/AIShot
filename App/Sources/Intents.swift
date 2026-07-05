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

/// Lets you drag-select a region via the Shortcuts app or Siri; brings AIShot
/// forward and waits for the selection (or cancellation) before returning.
struct CaptureRegionIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Region"
    static let description = IntentDescription("Lets you drag-select a region, saves it, and returns the file path.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let outcome = await AppModel.shared.captureRegionInteractive()
        return .result(value: outcome?.result.fileURL?.path ?? "")
    }
}

/// Captures the frontmost window via the Shortcuts app, Spotlight, or Siri.
struct CaptureWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Window"
    static let description = IntentDescription("Captures the frontmost window, saves it, and returns the file path.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let path = await AppModel.shared.captureFrontWindowReturningPath() ?? ""
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
        AppShortcut(
            intent: CaptureRegionIntent(),
            phrases: ["Capture a region with \(.applicationName)"],
            shortTitle: "Capture Region",
            systemImageName: "viewfinder"
        )
        AppShortcut(
            intent: CaptureWindowIntent(),
            phrases: ["Capture a window with \(.applicationName)"],
            shortTitle: "Capture Window",
            systemImageName: "macwindow"
        )
    }
}
