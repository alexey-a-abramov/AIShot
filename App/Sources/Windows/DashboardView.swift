import AppKit
import SwiftUI
import AIShotShared

/// The "admin"/dashboard window: quick capture, permission health, and recent
/// capture history.
struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List {
                Section("Capture") {
                    Button { model.captureRegion() } label: { Label("Region", systemImage: "viewfinder") }
                    Button { model.captureFrontWindow() } label: { Label("Window", systemImage: "macwindow") }
                    Button { model.captureFullScreen() } label: { Label("Full Screen", systemImage: "display") }
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
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            recentGrid
        }
        .task {
            await model.refreshRecent()
            await model.refreshPermissions()
        }
    }

    @ViewBuilder private var recentGrid: some View {
        if model.recent.isEmpty {
            ContentUnavailableView(
                "No captures yet",
                systemImage: "photo.on.rectangle",
                description: Text("Use the menu bar or ⌘⌥⇧4 to capture a region.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(model.recent) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            AsyncImage(url: entry.fileURL) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(height: 130)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(entry.fileURL?.lastPathComponent ?? "—")
                                .font(.caption).lineLimit(1).truncationMode(.middle)
                            Text("\(entry.pixelWidth)×\(entry.pixelHeight)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let url = entry.fileURL {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}
