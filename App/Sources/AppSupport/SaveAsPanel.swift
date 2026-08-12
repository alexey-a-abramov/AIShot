import AppKit
import UniformTypeIdentifiers
import AIShotCore

/// Wraps `NSSavePanel` for exporting a capture.
@MainActor
enum SaveAsPanel {
    struct Request {
        var suggestedName: String
        var directory: URL
        var format: ImageFormat
        /// Present as a sheet on this window when there is one; the capture
        /// overlay has no ordinary window to attach to.
        var host: NSWindow?
    }

    /// Returns the chosen URL, or nil if the user cancelled.
    static func run(_ request: Request) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = request.suggestedName
        panel.directoryURL = request.directory
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let type = UTType(request.format.utTypeIdentifier) {
            panel.allowedContentTypes = [type]
        }

        // The capture overlay sits at .screenSaver level; a panel ordered below
        // it would be invisible and the app would look wedged.
        panel.level = .modalPanel

        if let host = request.host {
            return await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: host) { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
