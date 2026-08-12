import Foundation
import AIShotCore

/// What a save should do — decided separately from performing it, so the rule
/// is unit-testable without an app bundle, a window, or a file panel.
public enum SaveIntent: Sendable, Equatable {
    /// Replace the file the image was opened from.
    case overwrite(URL, format: ImageFormat)
    /// Write a new file into `directory`.
    case newFile(directory: URL, fileName: String)
}

/// Decides what ⌘S does for an image the editor is holding.
///
/// Overwriting requires all of: a source file, that file still existing, the
/// user's preference, and a source format AIShot can re-encode. Anything else
/// falls back to writing a new file, which is always safe.
public func resolveSaveIntent(
    sourceURL: URL?,
    sourceExists: Bool,
    overwriteEnabled: Bool,
    settings: AppSettings,
    tag: String?,
    date: Date,
    timeZone: TimeZone = .current
) -> SaveIntent {
    if overwriteEnabled,
       let sourceURL,
       sourceExists,
       let format = ImageFormat(fileExtension: sourceURL.pathExtension) {
        return .overwrite(sourceURL, format: format)
    }

    let destination = SaveDestinationResolver().resolve(
        settings: settings, tag: tag, date: date, timeZone: timeZone
    )
    let name = FileNameFormatter(template: settings.fileNameTemplate)
        .fileName(format: settings.defaultFormat, date: date, timeZone: timeZone)
    return .newFile(directory: destination.directory, fileName: name)
}
