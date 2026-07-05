import AppKit
import SwiftUI

/// A small, non-activating HUD that fades in near the bottom of the screen after
/// a capture (e.g. "Copied to clipboard") and fades out shortly after.
@MainActor
final class CaptureHUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(message: String, thumbnail: NSImage?) {
        dismissTask?.cancel()

        let hosting = NSHostingView(rootView: CaptureHUD(message: message, thumbnail: thumbnail))
        hosting.layout()
        let size = hosting.fittingSize

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        panel.setContentSize(size)
        positionBottomCenter(panel, size: size)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled, let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
    }

    /// Hides the HUD immediately, skipping the fade — used right before a new
    /// capture starts so a still-fading HUD from the previous one (AIShot's
    /// own windows are no longer excluded from captures) can never appear in
    /// it.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func positionBottomCenter(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
    }
}

private struct CaptureHUD: View {
    let message: String
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable().scaledToFill()
                    .frame(width: 46, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(message).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .fixedSize()
    }
}
