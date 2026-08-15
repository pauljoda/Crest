import AppKit
import SwiftUI

@MainActor
final class BrowserShortcutSearchFieldCoordinator:
    NSObject,
    NSSearchFieldDelegate
{
    var text: Binding<String>

    init(text: Binding<String>) {
        self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else {
            return
        }
        text.wrappedValue = field.stringValue
    }
}
