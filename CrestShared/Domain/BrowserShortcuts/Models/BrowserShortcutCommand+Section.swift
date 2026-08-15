extension BrowserShortcutCommand {
    var section: BrowserShortcutSection {
        BrowserShortcutSectionPolicy.section(for: self)
    }
}
