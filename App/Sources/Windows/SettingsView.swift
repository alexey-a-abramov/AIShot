import AppKit
import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin
import AIShotCore
import AIShotPersistence
import AIShotShared

/// Preferences bound to `AppSettings`, persisted on change.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "command") }
            MCPSettingsView()
                .tabItem { Label("MCP", systemImage: "antenna.radiowaves.left.and.right") }
            PermissionsSettingsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 540, height: 460)
    }
}

private struct GeneralSettingsView: View {
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
            Section("Capture") {
                Picker("Format", selection: $model.settings.defaultFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                Toggle("Include cursor", isOn: $model.settings.includeCursor)
            }
            Section("After capture") {
                Picker("Default action", selection: $model.settings.postCaptureAction) {
                    Text("Copy to clipboard").tag(PostCaptureAction.copyToClipboard)
                    Text("Open editor").tag(PostCaptureAction.openEditor)
                    Text("Save only").tag(PostCaptureAction.saveOnly)
                }
            }
            Section("Notifications") {
                Toggle("Show notification", isOn: $model.settings.showNotification)
                Toggle("Play sound", isOn: $model.settings.playSound)
            }
            Section("Startup") {
                LaunchAtLogin.Toggle("Launch AIShot at login")
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.saveDirectory = url
            model.saveSettings()
        }
    }
}

private struct ShortcutsSettingsView: View {
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

private struct MCPSettingsView: View {
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

            Section("How to connect an AI agent") {
                Text("AIShot ships a local MCP server so agents (Claude Code, Claude Desktop) can capture and read your screen on-device. Register it with the Claude Code CLI:")
                    .font(.callout).foregroundStyle(.secondary)
                codeRow(addCommand)
                Text("Or add it to an MCP client's JSON config:")
                    .font(.callout).foregroundStyle(.secondary)
                codeRow(jsonConfig)
                Text("Capture and read tools work right away. Click and type tools are confirmation-gated when the toggle above is on. The server is local-only.")
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
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
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

private struct PermissionsSettingsView: View {
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
        .padding()
        .task { await model.refreshPermissions() }
    }
}
