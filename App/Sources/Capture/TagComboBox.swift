import AppKit
import SwiftUI

/// A native `NSComboBox` bridged to SwiftUI: the user can type a new tag or pick
/// an existing one from the dropdown. Shared by the post-capture prompt and the
/// dashboard's note/tag editor.
struct TagComboBox: NSViewRepresentable {
    @Binding var text: String
    var options: [String]
    /// Whether to grab keyboard focus when shown (used by the capture prompt).
    var focusOnAppear: Bool = false

    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox()
        combo.usesDataSource = false
        combo.completes = true
        combo.delegate = context.coordinator
        combo.addItems(withObjectValues: options)
        combo.stringValue = text
        combo.placeholderString = String(localized: "Type or pick a tag")
        if focusOnAppear { Self.focusWhenReady(combo) }
        return combo
    }

    func updateNSView(_ nsView: NSComboBox, context: Context) {
        // Don't overwrite the field while the user is typing in it (that would
        // collapse the insertion point / clobber autocomplete).
        if nsView.currentEditor() == nil, nsView.stringValue != text {
            nsView.stringValue = text
        }
        let current = nsView.objectValues as? [String] ?? []
        if current != options {
            nsView.removeAllItems()
            nsView.addItems(withObjectValues: options)
        }
    }

    /// Focuses the combo box once it's actually in a window (the window may not
    /// exist yet on the first run-loop turn after `makeNSView`).
    private static func focusWhenReady(_ combo: NSComboBox, attempts: Int = 6) {
        DispatchQueue.main.async {
            if let window = combo.window {
                window.makeFirstResponder(combo)
            } else if attempts > 0 {
                focusWhenReady(combo, attempts: attempts - 1)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        private let parent: TagComboBox
        init(_ parent: TagComboBox) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let combo = note.object as? NSComboBox else { return }
            parent.text = combo.stringValue
        }

        func comboBoxSelectionDidChange(_ note: Notification) {
            guard let combo = note.object as? NSComboBox, combo.indexOfSelectedItem >= 0,
                  let value = combo.itemObjectValue(at: combo.indexOfSelectedItem) as? String
            else { return }
            // Reflect the picked value immediately (the field's `stringValue`
            // isn't updated by selection on its own) and sync the binding.
            combo.stringValue = value
            parent.text = value
        }
    }
}
