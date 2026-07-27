import AppKit
import SwiftUI
import AIShotPersistence

/// Trailing details pane for the selected capture: a larger preview, the facts
/// (date, dimensions, mode, size on disk), inline note/tag editing, and the
/// actions that apply to one capture.
struct CaptureInspector: View {
    @EnvironmentObject private var model: AppModel
    let entry: HistoryEntry?

    @State private var note = ""
    @State private var tag = ""
    /// The entry whose values `note`/`tag` currently hold — until it matches
    /// the displayed entry, the fields still show the previous capture's text.
    @State private var loaded: HistoryEntry.ID?
    @State private var fileSize: Int?
    @State private var fileExists = true

    /// The entry the loaded edits belong to, for save-on-switch.
    private var editing: HistoryEntry? {
        guard let loaded, let entry, entry.id == loaded else { return nil }
        return entry
    }

    var body: some View {
        Group {
            if let entry {
                details(for: entry)
            } else {
                ContentUnavailableView(
                    "No capture selected",
                    systemImage: "sidebar.right",
                    description: Text("Select a capture to see its details.")
                )
            }
        }
        // Commit pending edits before switching — with an explicit Save button,
        // silently discarding what the user typed is a trap.
        .onChange(of: entry?.id) { _, _ in
            if let previous = editing, isDirty {
                let (savedNote, savedTag) = (note, tag)
                Task { await model.updateMetadata(for: previous, note: savedNote, tag: savedTag) }
            }
        }
        .task(id: entry?.id) { await load() }
    }

    private var isDirty: Bool {
        guard let entry, loaded == entry.id else { return false }
        let meta = model.metadata(for: entry)
        return note != (meta?.note ?? "") || tag != (meta?.tag ?? "")
    }

    @ViewBuilder
    private func details(for entry: HistoryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ThumbnailView(url: entry.fileURL, kind: entry.kind, size: .preview, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(verbatim: entry.fileURL?.lastPathComponent ?? "—")
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if !fileExists {
                    Label("The file was moved or deleted.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Date") {
                        Text(verbatim: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    // Synthesized entries (tagged files older than the history
                    // window) have no recorded pixel size.
                    if entry.pixelWidth > 0, entry.pixelHeight > 0 {
                        LabeledContent("Dimensions") {
                            Text(verbatim: "\(entry.pixelWidth)×\(entry.pixelHeight)")
                        }
                    }
                    // Unknown for tag-index entries — don't present a guess.
                    if entry.kind == .image, entry.pixelWidth > 0 {
                        LabeledContent("Mode") { Text(verbatim: entry.mode.displayName) }
                    }
                    LabeledContent("On disk") {
                        Text(verbatim: fileSize.map {
                            Int64($0).formatted(.byteCount(style: .file))
                        } ?? "—")
                    }
                }
                .font(.callout)

                Divider()

                // Only bind the fields once they hold THIS entry's values —
                // `body` renders before `.task(id:)` reloads them, which would
                // otherwise flash the previous capture's note for a frame.
                if loaded == entry.id {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note").font(.subheadline).foregroundStyle(.secondary)
                        TextField("What is this screenshot about?", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project tag").font(.subheadline).foregroundStyle(.secondary)
                        TagComboBox(text: $tag, options: model.knownTags)
                            .frame(height: 24)
                    }

                    Button("Save") {
                        Task {
                            await model.updateMetadata(for: entry, note: note, tag: tag)
                            await load()
                        }
                    }
                    .disabled(!isDirty)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if entry.kind == .image {
                        actionButton("Open in Editor", "pencil.tip.crop.circle") {
                            model.openInEditor(entry)
                        }
                        actionButton("Copy Image", "doc.on.doc") { model.copyToClipboard(entry) }
                        actionButton("Pin to Screen", "pin") { model.pin(entry) }
                    }
                    actionButton("Reveal in Finder", "folder") { model.revealInFinder(entry) }
                }
                .disabled(!fileExists)
            }
            .padding(16)
        }
    }

    private func actionButton(
        _ title: LocalizedStringKey, _ systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() async {
        guard let entry else {
            loaded = nil
            note = ""
            tag = ""
            fileSize = nil
            fileExists = true
            return
        }
        let meta = model.metadata(for: entry)
        note = meta?.note ?? ""
        tag = meta?.tag ?? ""
        loaded = entry.id
        // Clear first, so the previous capture's size isn't shown while the
        // probe runs.
        fileSize = nil

        guard let url = entry.fileURL else {
            fileExists = false
            return
        }
        // Stat off the main actor — a slow/network volume shouldn't stall the UI.
        let id = entry.id
        let probe = await Task.detached(priority: .utility) { () -> (Int?, Bool) in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return (values?.fileSize, FileManager.default.fileExists(atPath: url.path))
        }.value
        // A detached task isn't cancelled with the enclosing `.task(id:)`, so a
        // rapid selection change could otherwise land stale values here.
        guard !Task.isCancelled, self.entry?.id == id else { return }
        fileSize = probe.0
        fileExists = probe.1
    }
}
