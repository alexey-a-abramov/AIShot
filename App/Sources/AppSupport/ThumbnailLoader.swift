import AppKit
import CoreGraphics
import SwiftUI
import AIShotCapture
import AIShotPersistence

/// Thumbnail pixel budgets. Deliberately quantized to a few fixed sizes rather
/// than tracking the exact view size, so resizing the window can't thrash the
/// cache. Both are ≥ 2× their point size for Retina.
enum ThumbnailSize: Int, Sendable, Hashable {
    /// Grid cell (cards are ≤ ~240pt wide).
    case card = 512
    /// Inspector preview.
    case preview = 768
}

/// Why a thumbnail couldn't be produced — surfaced distinctly in the UI so a
/// deleted file never looks like a silently-broken image.
enum ThumbnailFailure: Error, Sendable, Equatable {
    /// The history entry has no file (captured without persisting).
    case noFile
    /// A path was recorded but nothing is there any more.
    case fileMissing
    /// Present, but not decodable.
    case unreadable
}

/// Decodes downsampled thumbnails off the main actor and caches them.
///
/// `NSCache` evicts automatically under memory pressure and is *not* `Sendable`,
/// so it stays isolated to this actor and is never handed out. `CGImage` is
/// `@unchecked Sendable`, so decoded thumbnails cross actor boundaries directly
/// with no boxing.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, CGImage>()
    /// In-flight decodes, so N cells asking for the same file decode once.
    private var inFlight: [NSString: Task<CGImage, Error>] = [:]
    /// Bumped by `invalidate` so a decode that was already running doesn't
    /// re-populate the cache with a stale image after it's been dropped.
    private var generation: [NSString: Int] = [:]

    init(totalCostLimit: Int = 96 * 1024 * 1024, countLimit: Int = 400) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
    }

    func thumbnail(for url: URL, kind: CaptureKind, size: ThumbnailSize) async throws -> CGImage {
        let key = Self.key(url, size)
        if let cached = cache.object(forKey: key) { return cached }
        if let running = inFlight[key] { return try await running.value }

        // Detached so the decode runs on the cooperative pool instead of
        // serializing on this actor — the actor only owns bookkeeping.
        let task = Task.detached(priority: .utility) { () throws -> CGImage in
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ThumbnailFailure.fileMissing
            }
            do {
                switch kind {
                case .image:
                    return try ImageCodec.thumbnail(contentsOf: url, maxPixelSize: size.rawValue)
                case .video:
                    return try await VideoThumbnail.frame(contentsOf: url, maxPixelSize: size.rawValue)
                }
            } catch {
                throw ThumbnailFailure.unreadable
            }
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let startedAt = generation[key] ?? 0
        let image = try await task.value
        // Skip the cache write if the file was invalidated mid-decode.
        if generation[key] ?? 0 == startedAt {
            cache.setObject(image, forKey: key, cost: max(1, image.bytesPerRow * image.height))
        }
        return image
    }

    /// Drops a file's cached thumbnails (e.g. after it's deleted or re-edited).
    func invalidate(_ url: URL) {
        for size in [ThumbnailSize.card, .preview] {
            let key = Self.key(url, size)
            cache.removeObject(forKey: key)
            // Bumping the generation makes any decode already in flight skip
            // its cache write, so a trashed file can't resurrect a thumbnail.
            generation[key, default: 0] += 1
            inFlight[key]?.cancel()
            inFlight[key] = nil
        }
    }

    private static func key(_ url: URL, _ size: ThumbnailSize) -> NSString {
        "\(url.standardizedFileURL.path)|\(size.rawValue)" as NSString
    }
}

/// Renders a capture's thumbnail with explicit loading and missing-file states.
///
/// Replaces `AsyncImage`, which is URLSession-backed and never loads `file://`
/// URLs — it silently showed its placeholder forever.
struct ThumbnailView: View {
    let url: URL?
    var kind: CaptureKind = .image
    var size: ThumbnailSize = .card
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading
        case success(CGImage)
        case failure(ThumbnailFailure)
    }

    /// Identity for `.task(id:)` — reloads when the file or requested size changes.
    private struct RequestKey: Equatable { var url: URL?; var size: ThumbnailSize }

    var body: some View {
        content
            .task(id: RequestKey(url: url, size: size)) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .success(let image):
            // `decorative` — the surrounding card carries the accessibility label.
            Image(decorative: image, scale: displayScale)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        case .loading:
            // No ProgressView: on a cache hit it would flash for one frame.
            placeholder(systemImage: "photo", label: nil)
        case .failure(.unreadable):
            // Present but undecodable — don't claim it's missing.
            placeholder(systemImage: "exclamationmark.triangle", label: Text("Can’t preview"))
        case .failure:
            placeholder(systemImage: "questionmark.folder", label: Text("File missing"))
        }
    }

    private func placeholder(systemImage: String, label: Text?) -> some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    if let label {
                        label.font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
    }

    private func load() async {
        guard let url else {
            phase = .failure(.noFile)
            return
        }
        // Don't reset to .loading on reload — keeping the old image avoids a
        // flash when only the size changes.
        let request = RequestKey(url: url, size: size)
        do {
            let image = try await ThumbnailLoader.shared.thumbnail(for: url, kind: kind, size: size)
            guard isCurrent(request) else { return }
            phase = .success(image)
        } catch let failure as ThumbnailFailure {
            guard isCurrent(request) else { return }
            phase = .failure(failure)
        } catch {
            guard isCurrent(request) else { return }
            phase = .failure(.unreadable)
        }
    }

    /// Awaiting the loader actor is not a cancellation point, so a `.task(id:)`
    /// that was superseded still resumes here. Without this guard a recycled
    /// grid cell could be overwritten with the previous capture's thumbnail.
    private func isCurrent(_ request: RequestKey) -> Bool {
        !Task.isCancelled && request == RequestKey(url: url, size: size)
    }
}
