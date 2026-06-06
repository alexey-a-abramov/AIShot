import SwiftUI

/// The "admin"/dashboard window: capture history, quick actions, and MCP +
/// permission status. Real content is wired up across Phase P1.
struct DashboardView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("History", systemImage: "clock")
                Label("Captures", systemImage: "photo.on.rectangle")
                Label("MCP Server", systemImage: "antenna.radiowaves.left.and.right")
                Label("Permissions", systemImage: "lock.shield")
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            ContentUnavailableView(
                "AIShot",
                systemImage: "camera.viewfinder",
                description: Text("Capture history, MCP status, and permissions appear here. (Phase P1)")
            )
        }
        .frame(minWidth: 680, minHeight: 440)
    }
}
