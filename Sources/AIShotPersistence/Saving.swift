import Foundation
import OSLog
import AIShotShared
import AIShotCore

/// Expands a filename template into a safe filename.
///
/// Tokens: `{date}` → `yyyy-MM-dd`, `{time}` → `HH.mm.ss`, `{app}` → owning app
/// name, `{seq}` → sequence number. Path-unsafe characters are sanitized.
public struct FileNameFormatter: Sendable {
    public var template: String
    public init(template: String) { self.template = template }

    public func fileName(
        format: ImageFormat,
        date: Date,
        app: String? = nil,
        sequence: Int? = nil,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        formatter.dateFormat = "HH.mm.ss"
        let timeString = formatter.string(from: date)

        var name = template
        name = name.replacingOccurrences(of: "{date}", with: dateString)
        name = name.replacingOccurrences(of: "{time}", with: timeString)
        name = name.replacingOccurrences(of: "{app}", with: app ?? "")
        name = name.replacingOccurrences(of: "{seq}", with: sequence.map(String.init) ?? "")

        let base = Self.sanitize(name)
        let safe = base.isEmpty ? "AIShot" : base
        return safe + "." + format.fileExtension
    }

    private static func sanitize(_ string: String) -> String {
        sanitizedComponent(string)
    }

    /// Makes a string safe to use as a single path component: path separators and
    /// other reserved characters become `-`, so a value like `a/b` can never
    /// become two directory levels.
    public static func sanitizedComponent(_ string: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return string
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Writes encoded image bytes to disk, creating the directory if needed and
/// avoiding clobbering existing files (appends ` (n)` on collision).
/// Why a capture could not be saved.
public enum CaptureSaveError: LocalizedError, Equatable {
    /// The encoded image had no bytes.
    case emptyImage
    /// The write reported success but nothing is at the path afterwards.
    case vanishedAfterWrite(URL)

    public var errorDescription: String? {
        switch self {
        case .emptyImage:
            "The capture contained no image data."
        case .vanishedAfterWrite(let url):
            "Saved to " + url.path + ", but the file is not there afterwards. "
                + "Something outside AIShot may be removing or syncing it."
        }
    }
}

public struct CaptureSaver: Sendable {
    public init() {}

    public func save(_ data: Data, fileName: String, to directory: URL) throws -> URL {
        let log = Logger.aishot("saving")

        guard !data.isEmpty else {
            // A zero-byte capture means the engine produced nothing; writing it
            // would leave an unopenable file and a history row pointing at it.
            log.error("refusing to save an empty capture to \(directory.path, privacy: .public)")
            throw CaptureSaveError.emptyImage
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log.error("cannot create \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let url = Self.uniqueURL(in: directory, fileName: fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("write failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // Verify rather than assume. A write that reports success but leaves
        // nothing behind - an external cleaner, a synced folder evicting the
        // file - must not be reported as a save, or history fills with rows
        // pointing at files that were never there.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let written = attributes?[.size] as? Int, written > 0 else {
            log.error("wrote \(data.count, privacy: .public) bytes to \(url.path, privacy: .public) but nothing is there afterwards")
            throw CaptureSaveError.vanishedAfterWrite(url)
        }

        log.info("saved \(written, privacy: .public) bytes to \(url.path, privacy: .public)")
        return url
    }

    /// Writes to an exact path, replacing what's there.
    ///
    /// Unlike `save`, this does **not** append " (2)" on collision: the caller
    /// has already chosen this path — either the user confirmed Replace in a
    /// save panel, or they asked to overwrite the file the editor opened — and
    /// silently writing somewhere else would defeat that.
    public func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func uniqueURL(in directory: URL, fileName: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (fileName as NSString).pathExtension
        let stem = (fileName as NSString).deletingPathExtension
        var index = 2
        repeat {
            let next = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(next)
            index += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }
}
