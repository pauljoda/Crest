import AppKit

@MainActor
enum AddressFocusAction {
    static func perform() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }
            guard let rootView = window.contentView?.superview else { return }
            guard let field = firstEditableTextField(in: rootView) else { return }
            window.makeFirstResponder(field)
            field.selectText(nil)
        }
    }

    static func resign() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private static func firstEditableTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for subview in view.subviews {
            if let field = firstEditableTextField(in: subview) {
                return field
            }
        }
        return nil
    }
}
