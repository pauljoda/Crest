enum BrowserLinkClickIntent: Equatable, Sendable {
    case navigate
    case peek
    case newTab
}

enum BrowserLinkClickModifier: String, Codable, CaseIterable, Equatable, Sendable {
    case option
    case command

    var title: String {
        switch self {
        case .option: "Option (⌥)"
        case .command: "Command (⌘)"
        }
    }

    var clickTitle: String {
        switch self {
        case .option: "Option-click"
        case .command: "Command-click"
        }
    }
}

enum BrowserLinkClickModifierPolicy {
    static func intent(
        isCommandModified: Bool,
        isOptionModified: Bool,
        peekModifier: BrowserLinkClickModifier
    ) -> BrowserLinkClickIntent {
        let isPeekModified =
            switch peekModifier {
            case .option: isOptionModified
            case .command: isCommandModified
            }
        if isPeekModified { return .peek }

        let isNewTabModified =
            switch peekModifier {
            case .option: isCommandModified
            case .command: isOptionModified
            }
        return isNewTabModified ? .newTab : .navigate
    }
}
