import AppKit
import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin
import AIShotCore
import AIShotPersistence
import AIShotShared

/// The pages shown in the Settings sidebar. Each is a focused page rather than a
/// dense tab, so the content pane on the right stays spacious.
private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, capture, tags, notifications, shortcuts, mcp, permissions, about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .capture: "Capture"
        case .tags: "Notes & Tags"
        case .notifications: "Notifications"
        case .shortcuts: "Shortcuts"
        case .mcp: "AI Agents"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .tags: "tag"
        case .notifications: "bell.badge"
        case .shortcuts: "command"
        case .mcp: "antenna.radiowaves.left.and.right"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .general: "Where screenshots are saved and how AIShot starts."
        case .capture: "What gets captured and what happens afterward."
        case .tags: "Attach a note and project tag to each capture."
        case .notifications: "Sound and banner shown after each capture."
        case .shortcuts: "Global hotkeys for every capture action."
        case .mcp: "Let on-device AI agents capture and read your screen."
        case .permissions: "System access AIShot needs to capture your screen."
        case .about: "Version, source code, and credits."
        }
    }
}

/// Preferences bound to `AppSettings`, persisted on change. A sidebar lists the
/// sections on the left; the selected page fills the wide pane on the right.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: SettingsSection? = .general

    var body: some View {
        // Pin the sidebar visible: this window has no toolbar (it's a hosted
        // accessory window), so there'd be no toggle to bring it back if it
        // collapsed. Navigation must always stay on the left.
        NavigationSplitView(columnVisibility: .constant(.all), sidebar: {
            List(selection: $selection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 240)
        }, detail: {
            page(for: selection ?? .general)
                .navigationSplitViewColumnWidth(min: 480, ideal: 580)
        })
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, idealWidth: 860, minHeight: 520, idealHeight: 580)
        // Persist whenever any page mutates the shared settings.
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
    }

    @ViewBuilder
    private func page(for section: SettingsSection) -> some View {
        SettingsPage(section: section) {
            switch section {
            case .general: GeneralPage()
            case .capture: CapturePage()
            case .tags: NotesTagsPage()
            case .notifications: NotificationsPage()
            case .shortcuts: ShortcutsPage()
            case .mcp: MCPPage()
            case .permissions: PermissionsPage()
            case .about: AboutPage()
            }
        }
    }
}

/// A spacious page chrome: a large header (icon, title, subtitle) above the
/// scrollable content of the page.
private struct SettingsPage<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: section.icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.title2.weight(.semibold))
                    Text(section.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)

            content
        }
        // Cap the content column to a comfortable reading width and center it,
        // so widening the window stays tidy instead of stretching controls
        // across the whole pane.
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Pages

private struct GeneralPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Saving") {
                LabeledContent("Folder") {
                    HStack {
                        Text(model.settings.saveDirectory.path)
                            .truncationMode(.middle).lineLimit(1).foregroundStyle(.secondary)
                        Button("Change…", action: chooseFolder)
                    }
                }
                TextField("Filename", text: $model.settings.fileNameTemplate)
            }
            Section("Startup") {
                LaunchAtLogin.Toggle("Launch AIShot at login")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            // Persisted by the root `.onChange(of: model.settings)`.
            model.settings.saveDirectory = url
        }
    }
}

private struct CapturePage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Capture") {
                Picker("Format", selection: $model.settings.defaultFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                Toggle("Include cursor", isOn: $model.settings.includeCursor)
                Toggle("Freeze screen before selecting", isOn: $model.settings.freezeBeforeRegionSelect)
            }
            Section("After capture") {
                Picker("Default action", selection: $model.settings.postCaptureAction) {
                    Text("Copy to clipboard").tag(PostCaptureAction.copyToClipboard)
                    Text("Open editor").tag(PostCaptureAction.openEditor)
                    Text("Save only").tag(PostCaptureAction.saveOnly)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotesTagsPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("After capture") {
                Toggle("Ask for a note and tag", isOn: $model.settings.captureMetadataEnabled)
                Toggle("Automatically apply the last tag", isOn: $model.settings.applyLastTag)
            }
            if let last = model.settings.lastTag, !last.isEmpty {
                Section("Last tag") {
                    LabeledContent("Tag") { Text(verbatim: last).foregroundStyle(.secondary) }
                    Button("Clear last tag") {
                        model.settings.lastTag = nil
                        model.settings.applyLastTag = false
                    }
                }
            }
            Section {
                Text("Notes and tags are saved beside your screenshots in aishot-metadata.json. Browse captures by tag in the Dashboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotificationsPage: View {
    @EnvironmentObject private var model: AppModel

    private static let soundNames = ["Pop", "Tink", "Glass", "Funk", "Submarine", "Ping", "Bottle", "Frog", "Sosumi"]

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Show notification", isOn: $model.settings.showNotification)
                Picker("Capture sound", selection: $model.settings.captureSoundName) {
                    Text("None").tag("None")
                    ForEach(Self.soundNames, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutsPage: View {
    var body: some View {
        Form {
            Section("Capture") {
                KeyboardShortcuts.Recorder("Region", name: .captureRegion)
                KeyboardShortcuts.Recorder("Window", name: .captureWindow)
                KeyboardShortcuts.Recorder("Full Screen", name: .captureFullScreen)
                KeyboardShortcuts.Recorder("Text (OCR)", name: .captureText)
                KeyboardShortcuts.Recorder("Scrolling", name: .scrollingCapture)
            }
            Section("Tools & actions") {
                KeyboardShortcuts.Recorder("Pick Color", name: .pickColor)
                KeyboardShortcuts.Recorder("Pin Last Capture", name: .pinLastCapture)
                KeyboardShortcuts.Recorder("Edit Last Capture", name: .editLastCapture)
                KeyboardShortcuts.Recorder("Recording", name: .toggleRecording)
            }
            Section {
                Text("Click a field and press keys to set a global shortcut; press ⌫ to clear it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MCPPage: View {
    @EnvironmentObject private var model: AppModel

    private let serverPath = "/Applications/AIShot.app/Contents/Helpers/aishot-mcp-server"
    private var addCommand: String { "claude mcp add aishot -- \(serverPath)" }
    private var jsonConfig: String {
        """
        {
          "mcpServers": {
            "aishot": { "command": "\(serverPath)" }
          }
        }
        """
    }

    var body: some View {
        Form {
            Section("Embedded MCP server") {
                Toggle("Enable MCP server", isOn: $model.settings.mcpEnabled)
                Toggle("Confirm before clicks/typing", isOn: $model.settings.mcpRequireConfirmationForInput)
            }

            Section("How it works") {
                Text("MCP (Model Context Protocol) is the open standard agents use to call tools. AIShot ships a local MCP server so assistants like Claude Code and Claude Desktop can see and act on your screen — entirely on your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                howItWorksRow("arrow.triangle.branch",
                              "An agent launches the bundled stdio bridge, which forwards JSON-RPC requests to AIShot. Every agent shares one capture authority, so your permission grants are reused.")
                howItWorksRow("camera.viewfinder",
                              "Capture & read tools — region/window/display capture, display and window enumeration, and OCR — run immediately.")
                howItWorksRow("cursorarrow.rays",
                              "Click, type, and app-switch tools synthesize input. They're confirmation-gated whenever the toggle above is on.")
                howItWorksRow("lock.shield",
                              "The server is loopback-only — images and recognized text never leave the device.")
            }

            Section("How to connect an AI agent") {
                Text("Register the server with the Claude Code CLI:")
                    .font(.callout).foregroundStyle(.secondary)
                codeRow(addCommand)
                Text("Or add it to an MCP client's JSON config:")
                    .font(.callout).foregroundStyle(.secondary)
                codeRow(jsonConfig)
                Text("Enable the server with the toggle above, then restart your agent so it picks up the new tools.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Server binary") {
                LabeledContent("Bundled path") {
                    Text(serverPath).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
                Text("In a dev build the binary is at .build/debug/aishot-mcp-server (run `swift build`).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func howItWorksRow(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func codeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
    }
}

private struct PermissionsPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            ForEach(Permission.allCases, id: \.self) { permission in
                HStack {
                    Label(permission.displayName, systemImage: permission.iconName)
                    Spacer()
                    let status = model.permissions[permission] ?? .notDetermined
                    if status == .granted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Request") { model.request(permission) }
                    }
                }
            }
            Section {
                Button("Re-check") { Task { await model.refreshPermissions() } }
                Text("After granting in System Settings, switch back to AIShot — status refreshes automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshPermissions() }
    }
}

private struct AboutPage: View {
    private let githubURL = URL(string: "https://github.com/aishot/aishot")!
    private let author = "Alexey Abramov"

    private var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    // Branded mark. AIShot has no bundled app icon yet, so a
                    // styled glyph reads better here than the generic macOS
                    // placeholder. Swap to `Image(nsImage: NSApp.applicationIconImage)`
                    // once a real AppIcon ships.
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                    Text(verbatim: "AIShot")
                        .font(.title2.weight(.semibold))
                    Text("AIShot captures regions, windows, and screens, lets you annotate them, and exposes the same tools to on-device AI agents over an embedded MCP server — all without anything leaving your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section {
                LabeledContent("Version") {
                    Text(verbatim: "\(marketingVersion) (\(buildNumber))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Author") {
                    Text(verbatim: author).foregroundStyle(.secondary)
                }
                LabeledContent("Source code") {
                    Link(destination: githubURL) {
                        Text(verbatim: "github.com/aishot/aishot")
                    }
                }
            }

            Section {
                Text(verbatim: "© 2026 \(author) · Built with Swift, SwiftUI & ScreenCaptureKit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
    }
}
