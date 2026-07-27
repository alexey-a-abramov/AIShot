import Foundation
import AIShotCore

/// Writes a captured image (encoded bytes, any ImageIO format) to the system
/// clipboard (`NSPasteboard`). Async so AppKit-backed implementations can hop
/// to the main actor.
public protocol ClipboardWriting: Sendable {
    func copyImage(_ data: Data) async throws
}

/// Presents a capture notification with a thumbnail and quick actions
/// (Copy / Annotate / Reveal). Backed by `UserNotifications`.
public protocol NotificationPresenting: Sendable {
    func present(_ result: CaptureResult) async
}

/// What kind of media a history entry points at. Screenshots and screen
/// recordings share one history so the dashboard can show both.
public enum CaptureKind: String, Sendable, Codable, CaseIterable {
    case image
    case video
}

/// One entry in the capture history shown in the dashboard.
public struct HistoryEntry: Sendable, Identifiable, Codable, Equatable {
    public var id: UUID
    public var fileURL: URL?
    public var createdAt: Date
    public var mode: CaptureMode
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var kind: CaptureKind

    public init(
        id: UUID = UUID(),
        fileURL: URL?,
        createdAt: Date,
        mode: CaptureMode,
        pixelWidth: Int,
        pixelHeight: Int,
        kind: CaptureKind = .image
    ) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.mode = mode
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.kind = kind
    }

    /// Resilient decoding: entries written before a field existed still load,
    /// so adding one never invalidates a user's history. (Same approach as
    /// `AppSettings.init(from:)`.)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        mode = try container.decode(CaptureMode.self, forKey: .mode)
        pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth) ?? 0
        pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight) ?? 0
        kind = try container.decodeIfPresent(CaptureKind.self, forKey: .kind) ?? .image
    }
}

/// Stores recent captures. Phase P1 backs this with a small SQLite/JSON store;
/// `InMemoryHistoryStore` covers tests and previews.
public protocol HistoryStore: Sendable {
    func record(_ entry: HistoryEntry) async throws
    func recent(limit: Int) async throws -> [HistoryEntry]
    /// Removes entries by id. Batched so deleting a selection rewrites the
    /// backing file once rather than once per entry.
    func remove(ids: Set<UUID>) async throws
}

/// A trivial, thread-safe history store for tests and SwiftUI previews.
public actor InMemoryHistoryStore: HistoryStore {
    private var entries: [HistoryEntry] = []
    public init() {}

    public func record(_ entry: HistoryEntry) async throws {
        entries.insert(entry, at: 0)
    }

    public func recent(limit: Int) async throws -> [HistoryEntry] {
        Array(entries.prefix(limit))
    }

    public func remove(ids: Set<UUID>) async throws {
        entries.removeAll { ids.contains($0.id) }
    }
}
