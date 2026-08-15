extension BrowserShortcutCommand {
    static func tabSelection(_ number: Int) -> BrowserShortcutCommand? {
        BrowserShortcutNumberedSelectionPolicy.tabCommand(number)
    }

    static func spaceSelection(_ number: Int) -> BrowserShortcutCommand? {
        BrowserShortcutNumberedSelectionPolicy.spaceCommand(number)
    }

    var tabNumber: Int? {
        BrowserShortcutNumberedSelectionPolicy.tabNumber(for: self)
    }

    var spaceNumber: Int? {
        BrowserShortcutNumberedSelectionPolicy.spaceNumber(for: self)
    }
}
