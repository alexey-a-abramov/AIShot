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
    func present(_ result: CaptureResult, sound: Bool) async
}

/// One entry in the capture history shown in the dashboard.
public struct HistoryEntry: Sendable, Identifiable, Codable, Equatable {
    public var id: UUID
    public var fileURL: URL?
    public var createdAt: Date
    public var mode: CaptureMode
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        id: UUID = UUID(),
        fileURL: URL?,
        createdAt: Date,
        mode: CaptureMode,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.mode = mode
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Stores recent captures. Phase P1 backs this with a small SQLite/JSON store;
/// `InMemoryHistoryStore` covers tests and previews.
public protocol HistoryStore: Sendable {
    func record(_ entry: HistoryEntry) async throws
    func recent(limit: Int) async throws -> [HistoryEntry]
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
}
