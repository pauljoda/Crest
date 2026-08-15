enum BrowserCommandPaletteSection: String, CaseIterable, Sendable {
    case tabs
    case actions
    case saved
    case history
    case otherSpaces
    case omnibox

    var title: String {
        switch self {
        case .tabs: "Tabs"
        case .actions: "Actions"
        case .saved: "Pinned & Saved"
        case .history: "History"
        case .otherSpaces: "Other Spaces"
        case .omnibox: "Extension"
        }
    }

    static let openTabsTitle = "Open Tabs"
}
