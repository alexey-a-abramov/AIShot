import AppKit
import SwiftUI

/// The small About box, opened from the menu bar.
///
/// AIShot is an `.accessory` app with no application menu, so the usual
/// "About <App>" item doesn't exist — this stands in for it. Settings has a
/// fuller About page; this is the quick "what am I running, and who wrote it"
/// answer, with the version in a form you can copy into a bug report.
struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            mark

            VStack(spacing: 3) {
                Text(verbatim: AppInfo.name)
                    .font(.title2.weight(.semibold))
                Text("Screen capture for humans and AI agents")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Click to copy — the one thing anyone opens an About box for.
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(AppInfo.versionString, forType: .string)
                copied = true
            } label: {
                HStack(spacing: 5) {
                    Text(verbatim: String(
                        format: String(localized: "Version %@"), AppInfo.versionString
                    ))
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(copied ? Text("Copied") : Text("Copy version"))

            Divider()

            VStack(spacing: 6) {
                LabeledContent("Author") { Text(verbatim: AppInfo.author) }
                LabeledContent("Source") {
                    Link(destination: AppInfo.repositoryURL) {
                        Text(verbatim: AppInfo.repositoryLabel)
                    }
                }
                LabeledContent("License") {
                    Link(destination: AppInfo.licenseURL) {
                        Text(verbatim: AppInfo.licenseName)
                    }
                }
            }
            .font(.callout)

            Divider()

            HStack(spacing: 10) {
                Button("Help") { model.openHelp() }
                Button("Settings…") { model.openSettings() }
            }

            Text(verbatim: AppInfo.copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(width: 320)
    }

    /// Branded mark. AIShot has no bundled AppIcon yet, so a styled glyph reads
    /// better than the generic macOS placeholder. Swap to
    /// `Image(nsImage: NSApp.applicationIconImage)` once a real icon ships.
    private var mark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 64, height: 64)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}
