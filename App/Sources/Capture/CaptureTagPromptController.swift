import AppKit
import SwiftUI

/// Presents a small floating panel after a capture so the user can attach a
/// note and a project tag. The tag field is a real `NSComboBox` (type a new tag
/// or pick an existing one). An "apply to the next captures" toggle lets a run
/// of related screenshots reuse the same tag without re-prompting.
@MainActor
final class CaptureTagPromptController: NSObject, NSWindowDelegate {
    /// What the user entered (nil completion argument means they skipped).
    struct Result {
        var note: String
        var tag: String?
        var applyToNext: Bool
    }

    private var panel: NSPanel?
    /// Called exactly once per prompt; cleared after firing so closing the panel
    /// (Save, Skip, or the window's close button) can never strand a capture.
    private var pending: ((Result?) -> Void)?

    func present(
        fileName: String,
        thumbnail: NSImage?,
        suggestedTag: String?,
        knownTags: [String],
        applyToNext: Bool,
        completion: @escaping (Result?) -> Void
    ) {
        // A prompt left open when the next capture arrives is treated as skipped.
        finish(nil)
        pending = completion

        let view = TagPromptView(
            fileName: fileName,
            thumbnail: thumbnail,
            note: "",
            tag: suggestedTag ?? "",
            applyToNext: applyToNext,
            knownTags: knownTags,
            onSave: { [weak self] result in self?.finish(result) },
            onSkip: { [weak self] in self?.finish(nil) }
        )

        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable]
        panel.title = String(localized: "Tag this capture")
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        self.panel = panel

        // Activate first: this panel appears right after a capture, which is
        // usually triggered while another app is frontmost. Requesting key
        // status before this app is active is a race that can leave Esc (and
        // typing) with the other app instead of the panel.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Dismisses a currently-shown prompt as if the user pressed Skip — used
    /// right before a new capture starts so a still-open prompt from a prior
    /// capture (AIShot's own windows are no longer excluded from captures)
    /// can never appear in it. A no-op if nothing is showing.
    func dismiss() {
        finish(nil)
    }

    /// Fires the pending completion once and tears down the panel.
    private func finish(_ result: Result?) {
        let completion = pending
        pending = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        completion?(result)
    }

    // Closing via the window's red button counts as "skip".
    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }
}

/// The contents of the post-capture tag/note panel.
private struct TagPromptView: View {
    let fileName: String
    let thumbnail: NSImage?
    @State var note: String
    @State var tag: String
    @State var applyToNext: Bool
    let knownTags: [String]
    let onSave: (CaptureTagPromptController.Result) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a note & tag").font(.headline)
                    Text(verbatim: fileName)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Note").font(.subheadline).foregroundStyle(.secondary)
                TextField("What is this screenshot about?", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Project tag").font(.subheadline).foregroundStyle(.secondary)
                TagComboBox(text: $tag, options: knownTags, focusOnAppear: true)
                    .frame(height: 24)
            }

            Toggle("Apply this tag to the next captures", isOn: $applyToNext)
                .font(.callout)

            HStack {
                Spacer()
                Button("Skip", role: .cancel, action: onSkip)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(.init(note: note, tag: tag, applyToNext: applyToNext))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}
