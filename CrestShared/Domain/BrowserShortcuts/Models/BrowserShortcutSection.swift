enum BrowserShortcutSection: String, CaseIterable, Identifiable, Sendable {
    case everyday
    case tabs
    case spaces
    case page
    case view

    var id: Self { self }
}
