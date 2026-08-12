import Foundation

/// How captures are filed inside the save directory.
public enum FolderOrganization: String, Sendable, Codable, CaseIterable {
    /// Everything in one folder (the default, and how AIShot has always behaved).
    case none
    /// `2026-08/`
    case byDate
    /// `ProjectX/`
    case byTag
    /// `ProjectX/2026-08/` — tag above date, so a project stays one folder.
    case byTagThenDate
}

/// Granularity of a date subfolder.
public enum DateFolderGranularity: String, Sendable, Codable, CaseIterable {
    case day, month, year

    var dateFormat: String {
        switch self {
        case .day: "yyyy-MM-dd"
        case .month: "yyyy-MM"
        case .year: "yyyy"
        }
    }
}

/// Where a capture will be written, and how that was decided.
public struct ResolvedDestination: Sendable, Equatable {
    /// The directory to write into (root + subpath).
    public var directory: URL
    /// The library root the capture belongs to.
    public var root: URL
    /// Sanitized components appended to `root`, in order.
    public var subpath: [String]

    public init(directory: URL, root: URL, subpath: [String]) {
        self.directory = directory
        self.root = root
        self.subpath = subpath
    }
}

/// Decides which directory a capture is saved into.
///
/// Pure: performs **no** I/O — it doesn't stat and it doesn't create anything.
/// `CaptureSaver.save` creates the whole nested path when it writes.
///
/// Note `AppSettings.lastSaveAsDirectory` is deliberately *not* an input. A
/// one-off "Save As…" must never silently redirect later automatic saves — the
/// dashboard, the tag sidebar and the metadata index are all rooted at
/// `saveDirectory`, so a drifting root would scatter the library.
public struct SaveDestinationResolver: Sendable {
    /// Longest a single folder component may be, in UTF-8 bytes. HFS+/APFS allow
    /// 255; staying well under keeps room for the file name.
    static let maxComponentBytes = 100

    public init() {}

    public func resolve(
        settings: AppSettings,
        tag: String?,
        date: Date,
        rootOverride: URL? = nil,
        timeZone: TimeZone = .current
    ) -> ResolvedDestination {
        let root = rootOverride ?? settings.saveDirectory
        var subpath: [String] = []

        switch settings.folderOrganization {
        case .none:
            break
        case .byTag:
            subpath.append(tagComponent(tag, settings: settings))
        case .byDate:
            subpath.append(dateComponent(date, settings: settings, timeZone: timeZone))
        case .byTagThenDate:
            subpath.append(tagComponent(tag, settings: settings))
            subpath.append(dateComponent(date, settings: settings, timeZone: timeZone))
        }

        let directory = subpath.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
        return ResolvedDestination(directory: directory, root: root, subpath: subpath)
    }

    private func tagComponent(_ tag: String?, settings: AppSettings) -> String {
        let cleaned = tag.map { Self.component($0) } ?? ""
        if !cleaned.isEmpty { return cleaned }
        let fallback = Self.component(settings.untaggedFolderName)
        return fallback.isEmpty ? "Unsorted" : fallback
    }

    private func dateComponent(_ date: Date, settings: AppSettings, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        // POSIX + explicit zone, like FileNameFormatter: a non-Gregorian regional
        // calendar would otherwise produce folders like `2569-08`.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = settings.dateFolderGranularity.dateFormat
        return formatter.string(from: date)
    }

    /// Sanitizes one folder component. Never returns something that can escape
    /// the root: separators are replaced, and `.`/`..` are rejected outright.
    static func component(_ raw: String) -> String {
        var value = FileNameFormatter.sanitizedComponent(raw)
        // Collapse internal whitespace runs so "a    b" doesn't make a ragged name.
        value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Leading dots would make the folder hidden, and "."/".." would traverse.
        while value.hasPrefix(".") { value.removeFirst() }
        value = value.trimmingCharacters(in: .whitespaces)
        guard value != "." && value != ".." else { return "" }

        if value.utf8.count > maxComponentBytes {
            var truncated = value
            while truncated.utf8.count > maxComponentBytes { truncated.removeLast() }
            value = truncated.trimmingCharacters(in: .whitespaces)
        }
        return value
    }
}
