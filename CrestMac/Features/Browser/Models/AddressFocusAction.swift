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
        guard let window = NSApp.keyWindow else { return }
        resign(in: window)
    }

    /// Gives up the responder that owns focus at this selection boundary.
    ///
    /// This must remain synchronous. Deferring the clear lets SwiftUI mount the
    /// destination page first, turning an address-focus dismissal into a clear
    /// of that page's newly restored responder instead.
    static func resign(in window: NSWindow) {
        window.makeFirstResponder(nil)
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
