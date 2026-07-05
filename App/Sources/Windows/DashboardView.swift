import AppKit
import SwiftUI
import AIShotPersistence
import AIShotShared

/// The "admin"/dashboard window: quick capture, tag navigation, permission
/// health, and the recent capture history with notes and project tags.
struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    /// Selected project tag to filter by; `nil` shows all captures.
    @State private var selectedTag: String?
    /// The capture currently being edited in the note/tag sheet.
    @State private var editing: HistoryEntry?
    /// Free-text search across note, tag, and file name.
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 232)
        } detail: {
            recentGrid
        }
        // `.toolbar` placement needs an NSToolbar, which this AppKit-hosted
        // window doesn't have — `.sidebar` attaches to the NavigationSplitView
        // sidebar instead and needs nothing further to render.
        .searchable(text: $searchText, placement: .sidebar, prompt: Text("Search notes, tags, or file names"))
        .task {
            await model.refreshRecent()
            await model.refreshPermissions()
        }
        // If the selected tag disappears (renamed/cleared), fall back to "All".
        .onChange(of: model.knownTags) { _, tags in
            if let tag = selectedTag, !tags.contains(tag) { selectedTag = nil }
        }
        .sheet(item: $editing) { entry in
            MetadataEditorSheet(entry: entry).environmentObject(model)
        }
    }

    private var sidebar: some View {
        List {
            Section("Capture") {
                Button { model.captureRegion() } label: { Label("Region", systemImage: "viewfinder") }
                Button { model.captureFrontWindow() } label: { Label("Window", systemImage: "macwindow") }
                Button { model.captureFullScreen() } label: { Label("Full Screen", systemImage: "display") }
                Button { model.captureAllDisplays() } label: { Label("All Displays", systemImage: "rectangle.on.rectangle") }
            }

            Section("Tags") {
                tagRow(Text("All captures"), systemImage: "square.grid.2x2", tag: nil)
                ForEach(model.knownTags, id: \.self) { tag in
                    tagRow(Text(verbatim: tag), systemImage: "tag", tag: tag)
                }
                if model.knownTags.isEmpty {
                    Text("Tag a capture to navigate by project here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                ForEach(Permission.allCases, id: \.self) { permission in
                    HStack {
                        Label(permission.displayName, systemImage: permission.iconName)
                        Spacer()
                        if model.permissions[permission] == .granted {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Grant") { model.request(permission) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private func tagRow(_ title: Text, systemImage: String, tag: String?) -> some View {
        Button {
            selectedTag = tag
        } label: {
            HStack {
                Label { title } icon: { Image(systemName: systemImage) }
                Spacer()
                if selectedTag == tag {
                    Image(systemName: "checkmark").font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredRecent: [HistoryEntry] {
        var entries = model.recent
        if let selectedTag {
            entries = entries.filter { model.metadata(for: $0)?.tag == selectedTag }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            let meta = model.metadata(for: entry)
            return (meta?.note.localizedCaseInsensitiveContains(query) ?? false)
                || (meta?.tag?.localizedCaseInsensitiveContains(query) ?? false)
                || (entry.fileURL?.lastPathComponent.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var emptyStateTitle: LocalizedStringKey {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No captures match your search"
        }
        return selectedTag == nil ? "No captures yet" : "No captures with this tag"
    }

    @ViewBuilder private var recentGrid: some View {
        let entries = filteredRecent
        if entries.isEmpty {
            ContentUnavailableView(
                emptyStateTitle,
                systemImage: "photo.on.rectangle",
                description: Text("Use the menu bar or ⌘⌥⇧4 to capture a region.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    ForEach(entries) { entry in
                        captureCard(entry)
                    }
                }
                .padding()
            }
        }
    }

    private func captureCard(_ entry: HistoryEntry) -> some View {
        let meta = model.metadata(for: entry)
        return VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: entry.fileURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let tag = meta?.tag, !tag.isEmpty {
                Label(tag, systemImage: "tag.fill")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
            }

            Text(entry.fileURL?.lastPathComponent ?? "—")
                .font(.caption).lineLimit(1).truncationMode(.middle)

            if let note = meta?.note, !note.isEmpty {
                Text(note)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("\(entry.pixelWidth)×\(entry.pixelHeight)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { reveal(entry) }
        .help(Text("Click to reveal in Finder · right-click to edit note & tag"))
        .contextMenu {
            Button("Edit note & tag…") { editing = entry }
            if entry.fileURL != nil {
                Button("Reveal in Finder") { reveal(entry) }
            }
        }
    }

    private func reveal(_ entry: HistoryEntry) {
        if let url = entry.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

/// Sheet to edit a capture's note and project tag after the fact.
private struct MetadataEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: HistoryEntry

    @State private var note: String = ""
    @State private var tag: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit note & tag").font(.headline)
            Text(verbatim: entry.fileURL?.lastPathComponent ?? "—")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)

            VStack(alignment: .leading, spacing: 6) {
                Text("Note").font(.subheadline).foregroundStyle(.secondary)
                TextField("What is this screenshot about?", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Project tag").font(.subheadline).foregroundStyle(.secondary)
                TagComboBox(text: $tag, options: model.knownTags)
                    .frame(height: 24)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task { await model.updateMetadata(for: entry, note: note, tag: tag); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            let meta = model.metadata(for: entry)
            note = meta?.note ?? ""
            tag = meta?.tag ?? ""
        }
    }
}
