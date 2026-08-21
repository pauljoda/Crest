import SwiftUI

extension BrowserShortcutStore {
    func keyboardShortcut(
        for command: BrowserShortcutCommand
    ) -> KeyboardShortcut? {
        shortcut(for: command).map(\.keyboardShortcut)
    }
}
