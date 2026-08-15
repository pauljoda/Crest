import SwiftUI

enum MobileBrowserKeyboardShortcut {
    static let downloadsKey = KeyEquivalent("j")
    static let downloadsModifiers: EventModifiers = [.command, .shift]
    static let stopLoadingKey = KeyEquivalent(".")
    static let stopLoadingModifiers: EventModifiers = .command
}
