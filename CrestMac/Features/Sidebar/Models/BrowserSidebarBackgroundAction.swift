enum BrowserSidebarBackgroundAction: CaseIterable, Equatable, Sendable {
    case editSpace
    case newSpace

    var title: String {
        switch self {
        case .editSpace: "Edit Space…"
        case .newSpace: "New Space…"
        }
    }

    var systemImage: String {
        switch self {
        case .editSpace: "pencil"
        case .newSpace: "plus"
        }
    }
}
