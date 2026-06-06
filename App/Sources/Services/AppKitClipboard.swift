import AppKit
import Foundation
import AIShotCore
import AIShotPersistence

/// `NSPasteboard`-backed clipboard writer. Hops to the main actor since
/// `NSPasteboard`/`NSImage` are main-thread APIs.
struct AppKitClipboard: ClipboardWriting {
    func copyImage(_ data: Data) async throws {
        try await MainActor.run {
            guard let image = NSImage(data: data) else {
                throw AIShotError.encodingFailed("clipboard: undecodable image data")
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }
}
