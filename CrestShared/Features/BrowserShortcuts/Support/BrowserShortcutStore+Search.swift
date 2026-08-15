extension BrowserShortcutStore {
    func commands(matching query: String) -> [BrowserShortcutCommand] {
        let catalog = BrowserShortcutPresentationCatalog()
        return BrowserShortcutCommand.userFacingCases.filter {
            catalog.matches(
                $0,
                currentShortcut: shortcut(for: $0),
                query: query
            )
        }
    }
}
