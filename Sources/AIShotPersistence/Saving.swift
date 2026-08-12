import Foundation
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
public struct CaptureSaver: Sendable {
    public init() {}

    public func save(_ data: Data, fileName: String, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = Self.uniqueURL(in: directory, fileName: fileName)
        try data.write(to: url, options: .atomic)
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
