import AppKit
import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin
import AIShotCore
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
                Picker("Format", selection: $model.settings.defaultFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                TextField("Filename", text: $model.settings.fileNameTemplate)
            }
            Section("After capture") {
                Toggle("Open editor after capture", isOn: $model.settings.openEditorAfterCapture)
                Toggle("Copy to clipboard", isOn: $model.settings.copyToClipboard)
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

    var body: some View {
        Form {
            Section("Embedded MCP server") {
                Toggle("Enable MCP server", isOn: $model.settings.mcpEnabled)
                LabeledContent("Port", value: String(model.settings.mcpPort))
                Toggle("Confirm before clicks/typing", isOn: $model.settings.mcpRequireConfirmationForInput)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
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
                        Text("Granted").foregroundStyle(.green)
                    } else {
                        Button("Request") { model.request(permission) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await model.refreshPermissions() }
    }
}
