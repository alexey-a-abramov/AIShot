import AppKit
import SwiftUI

/// Shows a large, centered self-timer countdown ("3… 2… 1…") before a delayed
/// capture fires, so the delay is visible rather than a silent pause.
@MainActor
final class CaptureCountdownController {
    private var panel: NSPanel?

    /// Counts down from `seconds` to 1 (about a second per step) and returns
    /// once the countdown finishes. A no-op if `seconds <= 0`.
    func run(seconds: Int) async {
        guard seconds > 0 else { return }
        let panel = makePanel()
        self.panel = panel
        panel.orderFrontRegardless()

        for n in stride(from: seconds, through: 1, by: -1) {
            update(panel, number: n)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        panel.orderOut(nil)
        self.panel = nil
    }

    private func update(_ panel: NSPanel, number: Int) {
        let hosting = NSHostingView(rootView: CountdownDial(number: number))
        hosting.layout()
        let size = hosting.fittingSize
        panel.contentView = hosting
        panel.setContentSize(size)
        center(panel, size: size)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func center(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }
}

private struct CountdownDial: View {
    let number: Int

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.system(size: 64, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 120, height: 120)
            .background(.black.opacity(0.55), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 2))
    }
}
