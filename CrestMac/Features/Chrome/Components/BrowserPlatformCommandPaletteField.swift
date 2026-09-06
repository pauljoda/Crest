import AppKit
import SwiftUI

/// A native single-line editor. The suffix is a noninteractive overlay on
/// its field editor, never an attributed replacement for the entered text.
struct BrowserPlatformCommandPaletteField: NSViewRepresentable {
    let model: BrowserCommandPaletteModel
    let identifier: String
    let focused: Bool

    func makeNSView(context: Context) -> NSTextField {
        makeField(coordinator: context.coordinator)
    }

    func makeField(coordinator: Coordinator) -> NSTextField {
        let field = NSTextField(string: model.query)
        field.isBordered = false
        field.drawsBackground = false
        field.font = .preferredFont(forTextStyle: .title2)
        field.placeholderString = String(localized: "Search or Enter URL…")
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.focusRingType = .none
        field.delegate = coordinator
        field.setAccessibilityLabel(String(localized: "Command Palette"))
        field.setAccessibilityIdentifier(identifier)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        coordinator.field = field
        model.applyCompletion = { [weak coordinator = coordinator] text, range in
            coordinator?.insert(text, replacementRange: range)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.currentEditor() == nil, field.stringValue != model.query {
            field.stringValue = model.query
        }
        context.coordinator.refreshSuffix()
        if focused, !context.coordinator.didRequestFocus {
            context.coordinator.didRequestFocus = true
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: BrowserCommandPaletteModel
        weak var field: NSTextField?
        let suffixLabel = CompletionLabel(
            rootView: BrowserURLCompletionSuffix(text: "", font: .title2, isVisible: false))
        var didRequestFocus = false

        init(model: BrowserCommandPaletteModel) {
            self.model = model
            super.init()
            suffixLabel.sizingOptions = []
            suffixLabel.setAccessibilityElement(false)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let editor = field?.currentEditor() as? NSTextView else { return }
            editor.isAutomaticTextCompletionEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.addSubview(suffixLabel)
            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(
                self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification,
                object: editor)
            editingChanged()
        }

        @objc private func selectionChanged(_ notification: Notification) { editingChanged() }

        func controlTextDidChange(_ notification: Notification) { editingChanged() }

        func controlTextDidEndEditing(_ notification: Notification) {
            model.rejectURLCompletion()
            suffixLabel.rootView.isVisible = false
            suffixLabel.removeFromSuperview()
        }

        func editingChanged() {
            guard let editor = field?.currentEditor() as? NSTextView else { return }
            if editor.undoManager?.isUndoing == true || editor.undoManager?.isRedoing == true {
                model.rejectURLCompletion()
            }
            model.updateCompletionEditing(
                text: editor.string, selection: editor.selectedRange(), isComposing: editor.hasMarkedText())
            refreshSuffix()
        }

        func refreshSuffix() {
            guard let field, let editor = field.currentEditor() as? NSTextView,
                !editor.hasMarkedText(), let proposal = model.urlCompletion,
                let window = editor.window
            else {
                suffixLabel.isHidden = true
                suffixLabel.rootView.isVisible = false
                field?.setAccessibilityHelp(nil)
                return
            }
            let screenRect = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            let rect = editor.convert(window.convertFromScreen(screenRect), from: nil)
            suffixLabel.rootView = BrowserURLCompletionSuffix(
                text: proposal.suffix, font: Font(field.font ?? .preferredFont(forTextStyle: .title2)))
            suffixLabel.frame = NSRect(
                x: rect.maxX, y: rect.minY, width: max(0, editor.bounds.maxX - rect.maxX), height: rect.height)
            suffixLabel.isHidden = false
            field.setAccessibilityHelp(
                String(localized: "URL completion: \(proposal.acceptedQuery). Press Tab or Right Arrow to accept."))
        }

        func insert(_ text: String, replacementRange: NSRange) {
            guard let editor = field?.currentEditor() as? NSTextView, !editor.hasMarkedText(),
                editor.string == model.query,
                editor.selectedRange() == NSRange(location: editor.string.utf16.count, length: 0)
            else { return }
            editor.breakUndoCoalescing()
            editor.insertText(text, replacementRange: replacementRange)
            editor.breakUndoCoalescing()
            editingChanged()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveRight(_:)):
                return model.acceptURLCompletion()
            case #selector(NSResponder.insertNewline(_:)):
                model.activateSelectedResult()
                return true
            case #selector(NSResponder.moveDown(_:)):
                model.moveSelection(by: 1)
                refreshSuffix()
                return true
            case #selector(NSResponder.moveUp(_:)):
                model.moveSelection(by: -1)
                refreshSuffix()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if model.urlCompletion != nil {
                    model.rejectURLCompletion()
                    refreshSuffix()
                    return true
                }
                return false
            default:
                return false
            }
        }
    }

    final class CompletionLabel: NSHostingView<BrowserURLCompletionSuffix> {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }
        override func accessibilityChildren() -> [Any]? { [] }
    }
}
