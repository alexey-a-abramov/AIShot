import AppKit
import QuickLook
import SwiftUI
import AIShotPersistence
import AIShotShared

/// The capture browser: quick capture actions and tag navigation on the left,
/// a date-grouped grid of captures in the middle, and a details inspector on
/// the right.
struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    @State private var filter: SidebarFilter? = .all
    @State private var searchText = ""
    @State private var selection = Set<HistoryEntry.ID>()
    /// Anchor for shift-click range selection.
    @State private var selectionAnchor: HistoryEntry.ID?
    @State private var showsInspector = true
    @State private var quickLookURL: URL?
    @State private var deleteTargets: [HistoryEntry] = []
    @State private var bulkTag = ""
    @State private var showsBulkTagField = false
    @State private var columnCount = 3
    @FocusState private var gridFocused: Bool

    /// Derived state, recomputed only when an input actually changes.
    ///
    /// Deriving these inside `body` instead re-ran the whole filter/sort on
    /// every hover and every `AppModel` publish — several times per pass, since
    /// the grid, the count badge and the inspector each need them.
    @State private var visible: [HistoryEntry] = []
    @State private var groups: [EntryGroup] = []
    @State private var byID: [HistoryEntry.ID: HistoryEntry] = [:]

    /// Which captures the grid is showing.
    private enum SidebarFilter: Hashable {
        case all
        case tag(String)
    }

    private struct EntryGroup: Identifiable, Equatable {
        var group: CaptureDateGroup
        var entries: [HistoryEntry]
        var id: CaptureDateGroup { group }
    }

    private static let cardMinWidth: CGFloat = 176
    private static let cardMaxWidth: CGFloat = 240
    private static let cardSpacing: CGFloat = 12
    private static let gridPadding: CGFloat = 20

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 240)
        } detail: {
            browser
                .inspector(isPresented: $showsInspector) {
                    // With several selected, the per-capture editor doesn't
                    // apply — the bulk bar in the grid takes over instead.
                    CaptureInspector(entry: selection.count == 1 ? selectedEntry : nil,
                                     multiSelectionCount: selection.count)
                        .environmentObject(model)
                        .inspectorColumnWidth(min: 250, ideal: 300, max: 380)
                }
                .navigationSplitViewColumnWidth(min: 400, ideal: 640)
        }
        .navigationSplitViewStyle(.balanced)
        // `.toolbar` placement needs an NSToolbar, which this AppKit-hosted
        // window doesn't have — `.sidebar` renders with nothing further.
        .searchable(text: $searchText, placement: .sidebar,
                    prompt: Text("Search text in images, notes, tags, or file names"))
        // Column minimums (200 + 400 + 250) plus dividers set the real floor.
        .frame(minWidth: 880, idealWidth: 980, minHeight: 520, idealHeight: 660)
        .task {
            await model.refreshRecent()
            await model.refreshPermissions()
            recompute()
            // Build the full-text index in the background so searching by the
            // words inside a screenshot works.
            model.indexCapturesForSearch()
        }
        .onChange(of: model.recent) { _, _ in recompute() }
        .onChange(of: model.captureMeta) { _, _ in recompute() }
        .onChange(of: model.textMatches) { _, _ in recompute() }
        .onChange(of: filter) { _, _ in recompute() }
        .onChange(of: searchText) { _, query in
            recompute()
            Task { await model.updateTextMatches(for: query) }
        }
        // If the selected tag disappears (renamed/cleared), fall back to "All".
        .onChange(of: model.knownTags) { _, tags in
            if case .tag(let name) = filter, !tags.contains(name) { filter = .all }
        }
        .quickLookPreview($quickLookURL)
        .confirmationDialog(
            deleteTargets.count == 1
                ? Text("Move “\(deleteTargets[0].fileURL?.lastPathComponent ?? "")” to the Trash?")
                : Text("Move \(deleteTargets.count) captures to the Trash?"),
            isPresented: Binding(get: { !deleteTargets.isEmpty },
                                 set: { if !$0 { deleteTargets = [] } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                let targets = deleteTargets
                deleteTargets = []
                selection.subtract(targets.map(\.id))
                Task { await model.delete(targets) }
            }
            Button("Cancel", role: .cancel) { deleteTargets = [] }
        } message: {
            Text("You can restore it from the Trash.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $filter) {
            Section("Capture") {
                sidebarAction("Region", "viewfinder") { model.captureRegion() }
                sidebarAction("Window", "macwindow") { model.captureFrontWindow() }
                sidebarAction("Full Screen", "display") { model.captureFullScreen() }
                sidebarAction("All Displays", "rectangle.on.rectangle") { model.captureAllDisplays() }
            }

            Section("Tags") {
                Label("All captures", systemImage: "square.grid.2x2")
                    .tag(SidebarFilter.all)
                ForEach(model.knownTags, id: \.self) { tag in
                    Label(tag, systemImage: "tag")
                        .tag(SidebarFilter.tag(tag))
                }
                if model.knownTags.isEmpty {
                    Text("Tag a capture to navigate by project here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Only shown when something actually needs doing — the full
            // always-on list duplicates Settings › Permissions and is noise in
            // a browsing window.
            let ungranted = Permission.allCases.filter { model.permissions[$0] != .granted }
            if !ungranted.isEmpty {
                Section("Needs attention") {
                    ForEach(ungranted, id: \.self) { permission in
                        HStack {
                            Label(permission.displayName, systemImage: permission.iconName)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Grant") { model.request(permission) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarAction(
        _ title: LocalizedStringKey, _ systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    private var browser: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if selection.count > 1 { bulkBar; Divider() }
            grid
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Actions that apply to the whole selection. Only shown for 2+ captures —
    /// a single selection is handled by the inspector.
    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text(verbatim: String(
                format: String(localized: "%lld selected"), selection.count
            ))
            .font(.callout.weight(.medium))

            Button("Clear") { selection.removeAll() }
                .buttonStyle(.borderless)

            Spacer(minLength: 0)

            if showsBulkTagField {
                TagComboBox(text: $bulkTag, options: model.knownTags, focusOnAppear: true)
                    .frame(width: 180, height: 22)
                Button("Apply") {
                    let targets = selectedEntries
                    let tag = bulkTag
                    showsBulkTagField = false
                    bulkTag = ""
                    Task { await model.applyTag(tag, to: targets) }
                }
                .disabled(bulkTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") { showsBulkTagField = false; bulkTag = "" }
                    .buttonStyle(.borderless)
            } else {
                Button {
                    bulkTag = model.settings.lastTag ?? ""
                    showsBulkTagField = true
                } label: {
                    Label("Tag…", systemImage: "tag")
                }
                Button {
                    model.copyToClipboard(selectedEntries)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(selectedEntries.allSatisfy { $0.kind != .image })
                Button(role: .destructive) {
                    deleteTargets = selectedEntries
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Captures").font(.title2.weight(.semibold))
                Text("Your recent captures, with notes and project tags.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            // Only appears when history references files that are gone (moved
            // or deleted outside AIShot), so it's invisible in the normal case.
            let missing = model.missingEntries.count
            if missing > 0 {
                Button {
                    Task { await model.removeMissingEntries() }
                } label: {
                    Label {
                        Text(verbatim: String(
                            format: String(localized: "Clear %lld missing"), missing
                        ))
                    } icon: {
                        Image(systemName: "questionmark.folder")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(Text("Remove history entries whose files no longer exist"))
            }

            Text(verbatim: visible.count.formatted())
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(.quaternary, in: Capsule())

            // The only way to bring the inspector back — `.inspector` normally
            // puts its affordance in a toolbar, and this window has none.
            Button { showsInspector.toggle() } label: {
                Label(showsInspector ? "Hide details" : "Show details",
                      systemImage: "sidebar.trailing")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(showsInspector ? Text("Hide details") : Text("Show details"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var grid: some View {
        if groups.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(
                            .adaptive(minimum: Self.cardMinWidth, maximum: Self.cardMaxWidth),
                            spacing: Self.cardSpacing,
                            // Cards vary in height (optional tag + note), so
                            // top-align or a row reads ragged.
                            alignment: .top
                        )],
                        spacing: 14,
                        pinnedViews: [.sectionHeaders]
                    ) {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    CaptureCard(
                                        entry: entry,
                                        metadata: model.metadata(for: entry),
                                        timestamp: group.group.timestamp(for: entry.createdAt),
                                        snippet: model.textSnippet(for: entry, query: searchText),
                                        isSelected: selection.contains(entry.id),
                                        onSelect: { select(entry) },
                                        onOpen: { open(entry) },
                                        menu: { AnyView(contextMenu(for: entry)) }
                                    )
                                }
                            } header: {
                                Text(group.group.title)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .background(.bar)
                            }
                        }
                    }
                    .padding(.horizontal, Self.gridPadding)
                    .padding(.bottom, Self.gridPadding)
                    // Measured on the grid, not the ScrollView, whose width
                    // includes the legacy scroller when it's always visible.
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        let usable = width + Self.cardSpacing
                        columnCount = max(1, Int(usable / (Self.cardMinWidth + Self.cardSpacing)))
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($gridFocused)
                .defaultFocus($gridFocused, true)
                // Arrows repeat; one-shot actions must not, or holding the key
                // re-opens the editor / re-arms the delete dialog.
                .onKeyPress(.leftArrow) { move(by: -1) }
                .onKeyPress(.rightArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -columnCount) }
                .onKeyPress(.downArrow) { move(by: columnCount) }
                .onKeyPress(.space, phases: .down) { _ in previewSelected() }
                .onKeyPress(.return, phases: .down) { _ in openSelected() }
                .onKeyPress(.delete, phases: .down) { _ in requestDeleteSelected() }
                .onKeyPress(.escape, phases: .down) { _ in
                    guard !selection.isEmpty else { return .ignored }
                    selection.removeAll()
                    return .handled
                }
                .onKeyPress(KeyEquivalent("a"), phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    selection = Set(visible.map(\.id))
                    return .handled
                }
                .onChange(of: selection) { old, new in
                    // Scroll to follow a keyboard move (exactly one selected and
                    // it changed), not to fight a multi-select.
                    guard new.count == 1, let id = new.first, old.first != id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if case .tag = filter {
            ContentUnavailableView(
                "No captures with this tag",
                systemImage: "tag",
                description: Text("Tag a capture to navigate by project here.")
            )
        } else {
            ContentUnavailableView(
                "No captures yet",
                systemImage: "photo.on.rectangle",
                description: Text("Use the menu bar or ⌘⌥⇧4 to capture a region.")
            )
        }
    }

    @ViewBuilder
    private func contextMenu(for entry: HistoryEntry) -> some View {
        if entry.kind == .image {
            Button("Open in Editor") { open(entry) }
        }
        Button("Quick Look") { quickLookURL = entry.fileURL }
        Button("Edit note & tag…") {
            selection = [entry.id]
            showsInspector = true
        }
        Divider()
        if entry.kind == .image {
            Button("Copy Image") { model.copyToClipboard(entry) }
            Button("Pin to Screen") { model.pin(entry) }
        }
        Button("Reveal in Finder") { model.revealInFinder(entry) }
        Divider()
        // Right-clicking inside a multi-selection acts on the whole selection,
        // matching Finder.
        if selection.count > 1, selection.contains(entry.id) {
            Button("Move \(selection.count) to Trash", role: .destructive) {
                deleteTargets = selectedEntries
            }
        } else {
            Button("Move to Trash", role: .destructive) { deleteTargets = [entry] }
        }
    }

    // MARK: - Derived state

    /// Recomputes the filtered/grouped view of the history. Cheap: all inputs
    /// are in memory (file existence was resolved during `refreshMetadata`).
    private func recompute() {
        var entries: [HistoryEntry]
        switch filter {
        case .tag(let tag):
            // Reads the metadata index, not just the recent window, so a tag
            // whose captures are older still shows them.
            entries = model.entries(taggedWith: tag)
        case .all, nil:
            entries = model.recent
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            entries = entries.filter { entry in
                let meta = model.metadata(for: entry)
                return (meta?.note.localizedCaseInsensitiveContains(query) ?? false)
                    || (meta?.tag?.localizedCaseInsensitiveContains(query) ?? false)
                    || (entry.fileURL?.lastPathComponent.localizedCaseInsensitiveContains(query) ?? false)
                    // Words *inside* the image, from the OCR index.
                    || model.textSnippet(for: entry, query: query) != nil
            }
        }

        visible = entries
        byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let now = Date()
        groups = Dictionary(grouping: entries) { CaptureDateGroup.of($0.createdAt, now: now) }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { EntryGroup(group: $0.key, entries: $0.value) }

        // Drop selections that are no longer on screen (deleted, filtered out,
        // or searched away) so the inspector never points at nothing.
        let stillVisible = selection.filter { byID[$0] != nil }
        if stillVisible.count != selection.count { selection = stillVisible }
        if let anchor = selectionAnchor, byID[anchor] == nil { selectionAnchor = nil }
    }

    private var selectedEntry: HistoryEntry? {
        selection.count == 1 ? selection.first.flatMap { byID[$0] } : nil
    }

    /// The selected captures, in the order they appear in the grid.
    private var selectedEntries: [HistoryEntry] {
        visible.filter { selection.contains($0.id) }
    }

    // MARK: - Actions

    /// Click selection, honoring the standard macOS modifiers: ⌘ toggles,
    /// ⇧ extends from the anchor, a plain click replaces.
    private func select(_ entry: HistoryEntry) {
        gridFocused = true
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selection.contains(entry.id) {
                selection.remove(entry.id)
            } else {
                selection.insert(entry.id)
                selectionAnchor = entry.id
            }
        } else if modifiers.contains(.shift), let anchor = selectionAnchor,
                  let from = visible.firstIndex(where: { $0.id == anchor }),
                  let to = visible.firstIndex(where: { $0.id == entry.id }) {
            // Replace rather than union, so shift-clicking a nearer item
            // shrinks the range like it does in Finder.
            let range = from <= to ? from...to : to...from
            selection = Set(visible[range].map(\.id))
        } else {
            selection = [entry.id]
            selectionAnchor = entry.id
        }
    }

    private func open(_ entry: HistoryEntry) {
        if entry.kind == .video {
            quickLookURL = entry.fileURL
        } else {
            model.openInEditor(entry)
        }
    }

    private func openSelected() -> KeyPress.Result {
        guard let entry = selectedEntry else { return .ignored }
        open(entry)
        return .handled
    }

    private func previewSelected() -> KeyPress.Result {
        guard let url = selectedEntry?.fileURL else { return .ignored }
        quickLookURL = url
        return .handled
    }

    private func requestDeleteSelected() -> KeyPress.Result {
        let targets = selectedEntries
        guard !targets.isEmpty else { return .ignored }
        deleteTargets = targets
        return .handled
    }

    /// Moves the selection through the flat visible order. Vertical steps are
    /// approximate across a date-group boundary (each group has its own partial
    /// last row) — the usual trade-off in a grouped photo grid.
    private func move(by offset: Int) -> KeyPress.Result {
        guard !visible.isEmpty else { return .ignored }
        // From a multi-selection, arrow keys collapse to the end nearest the
        // direction of travel and move on from there, like Finder.
        let current = selection.count == 1
            ? selection.first
            : (offset < 0 ? selectedEntries.first : selectedEntries.last)?.id
        guard let current, let index = visible.firstIndex(where: { $0.id == current }) else {
            let first = visible[0].id
            selection = [first]
            selectionAnchor = first
            return .handled
        }
        let next = min(max(index + offset, 0), visible.count - 1)
        let id = visible[next].id
        selection = [id]
        selectionAnchor = id
        return .handled
    }
}

/// One capture in the grid. A separate view so hovering repaints just this
/// card instead of invalidating the whole dashboard body.
private struct CaptureCard: View {
    let entry: HistoryEntry
    let metadata: CaptureMetadata?
    let timestamp: String
    /// OCR excerpt explaining why this matched the current search, if it did.
    let snippet: String?
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let menu: () -> AnyView

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(url: entry.fileURL, kind: entry.kind, size: .card, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 10.0, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                // `mode` is unknown for entries synthesized from the tag index
                // (marked by a zero pixel size), so only badge what we know.
                if entry.kind == .video {
                    badge(entry.kind.iconName, String(localized: "Recording"))
                } else if entry.pixelWidth > 0 {
                    badge(entry.mode.iconName, entry.mode.displayName)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.fileURL?.lastPathComponent ?? "—")
                    .font(.callout.weight(.medium))
                    .lineLimit(1).truncationMode(.middle)

                HStack(spacing: 5) {
                    Text(verbatim: timestamp)
                    // Dimensions are unknown for entries synthesized from the
                    // tag index; `verbatim` keeps 1254 from becoming "1.254".
                    if entry.pixelWidth > 0, entry.pixelHeight > 0 {
                        Text(verbatim: "·")
                        Text(verbatim: "\(entry.pixelWidth)×\(entry.pixelHeight)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let tag = metadata?.tag, !tag.isEmpty {
                    Label(tag, systemImage: "tag.fill")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }

                // A search hit on the text inside the image — show the excerpt
                // so it's obvious why this capture matched.
                if let snippet, !snippet.isEmpty {
                    Label {
                        Text(verbatim: snippet).lineLimit(2)
                    } icon: {
                        Image(systemName: "text.viewfinder")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else if let note = metadata?.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(isSelected ? 0.9 : (isHovered ? 0.55 : 0.2)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        // Must precede the single-tap gesture, or the double-click never fires.
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
        .contextMenu { menu() }
        // Vend the file URL (not a bitmap) so receivers get a real file with
        // its name intact. No state is mutated here — doing so mid-drag makes
        // AppKit snapshot a stale preview.
        .modifier(DraggableFile(url: entry.fileURL))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: entry.fileURL?.lastPathComponent ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func badge(_ systemImage: String, _ label: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption2)
            .padding(5)
            .background(.thinMaterial, in: Circle())
            .padding(6)
            .help(Text(verbatim: label))
    }
}

/// Attaches drag-out only when there's a real file behind the card — an
/// unconditional `.onDrag` would start an empty drag session.
private struct DraggableFile: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        } else {
            content
        }
    }
}

/// Day buckets used for the grid's pinned section headers.
private enum CaptureDateGroup: Int, CaseIterable, Hashable {
    case today, yesterday, thisWeek, earlier

    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This Week"
        case .earlier: "Earlier"
        }
    }

    static func of(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> CaptureDateGroup {
        // A future timestamp (clock skew, or a file with a future mtime) would
        // otherwise sort to the top of the oldest bucket.
        if date > now { return .today }
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        // A rolling 7-day window, not `.weekOfYear` — the calendar week
        // collapses to nothing on its own first weekday (Sunday in en_US,
        // Monday in fr/es), which made the section vanish on those days.
        if let cutoff = calendar.date(byAdding: .day, value: -7, to: now), date >= cutoff {
            return .thisWeek
        }
        return .earlier
    }

    /// Timestamp shown on a card — only as precise as the group needs.
    func timestamp(for date: Date) -> String {
        switch self {
        case .today, .yesterday:
            return date.formatted(date: .omitted, time: .shortened)
        case .thisWeek:
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .earlier:
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}
