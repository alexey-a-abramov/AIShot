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
        .frame(width: 520, height: 380)
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
            KeyboardShortcuts.Recorder("Capture Region", name: .captureRegion)
            KeyboardShortcuts.Recorder("Capture Window", name: .captureWindow)
            KeyboardShortcuts.Recorder("Capture Full Screen", name: .captureFullScreen)
        }
        .formStyle(.grouped)
        .padding()
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
