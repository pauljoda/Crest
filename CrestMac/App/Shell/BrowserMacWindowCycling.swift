import AppKit

/// The Mac's "Move focus to next window" shortcut, ⌘` unless the person
/// changed it in Keyboard Shortcuts, and what it does in Crest: it brings
/// Crest's backmost window forward, or with Shift, the window behind the front
/// one, as AppKit does. A focused Chromium page keeps the key from AppKit, so
/// Crest cycles its windows itself, Quick Windows among them.
@MainActor
struct BrowserMacWindowCycling {
    // MARK: - Static Variables

    /// The symbolic hotkey macOS keeps "Move focus to next window" under.
    private static let symbolicHotKey = "27"
    /// ⌘`, the shortcut until the person changes it.
    private static let standard = BrowserMacWindowCycling(keyCode: 50, modifiers: .command)

    /// The shortcut as the person has it, or nil when they turned it off.
    private static var current: BrowserMacWindowCycling? {
        guard
            let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(
                forKey: "AppleSymbolicHotKeys"),
            let entry = hotKeys[symbolicHotKey] as? [String: Any]
        else { return standard }
        if let enabled = entry["enabled"] as? Bool, !enabled { return nil }
        guard let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [Int],
            parameters.count == 3, let keyCode = UInt16(exactly: parameters[1]), parameters[2] >= 0
        else { return standard }
        return BrowserMacWindowCycling(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(parameters[2])).intersection(.deviceIndependentFlagsMask))
    }

    // MARK: - Variables

    private let keyCode: UInt16
    private let modifiers: NSEvent.ModifierFlags

    // MARK: - Actions - Cycling

    /// Moves focus to another of Crest's windows when `event` is the
    /// shortcut, the other way with Shift. Answers whether it did.
    static func cycle(for event: NSEvent) -> Bool {
        guard let shortcut = current, event.keyCode == shortcut.keyCode else { return false }
        let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([
            .capsLock, .numericPad, .function,
        ])
        let reversed = held == shortcut.modifiers.union(.shift) && !shortcut.modifiers.contains(.shift)
        guard held == shortcut.modifiers || reversed else { return false }
        // The windows AppKit cycles through: Crest's own on this Space, front
        // to back, that can take focus.
        let windows = NSApp.orderedWindows.filter {
            $0.isVisible && !$0.isMiniaturized && $0.canBecomeKey && $0.isOnActiveSpace && $0.level == .normal
                && $0.sheetParent == nil && !$0.isExcludedFromWindowsMenu
                && !$0.collectionBehavior.contains(.ignoresCycle)
        }
        guard windows.count > 1, let back = windows.last else { return false }
        if reversed {
            windows[1].makeKeyAndOrderFront(nil)
            windows[0].order(.below, relativeTo: back.windowNumber)
        } else {
            back.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
