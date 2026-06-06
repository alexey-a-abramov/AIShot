import SwiftUI

/// Preferences. Phase P1 binds these tabs to `AppSettings` (save location,
/// format, shortcuts, MCP server, and permission status).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            placeholder("Shortcuts (Phase P1)")
                .tabItem { Label("Shortcuts", systemImage: "command") }

            placeholder("MCP Server (Phase P1b)")
                .tabItem { Label("MCP", systemImage: "antenna.radiowaves.left.and.right") }

            placeholder("Permissions (Phase P1)")
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 500, height: 340)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Save location", value: "~/Pictures/AIShot")
            LabeledContent("Format", value: "PNG")
            Toggle("Copy to clipboard", isOn: .constant(true))
            Toggle("Show notification", isOn: .constant(true))
            Toggle("Launch at login", isOn: .constant(false))
        }
        .formStyle(.grouped)
        .padding()
    }
}
