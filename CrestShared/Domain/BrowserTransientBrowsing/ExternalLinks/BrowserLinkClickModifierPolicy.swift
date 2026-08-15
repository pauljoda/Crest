import Foundation

enum BrowserLinkClickModifierPolicy {
    static func intent(
        isCommandModified: Bool,
        isOptionModified: Bool,
        peekModifier: BrowserLinkClickModifier
    ) -> BrowserLinkClickIntent {
        let isPeekModified = switch peekModifier {
        case .option: isOptionModified
        case .command: isCommandModified
        }
        if isPeekModified { return .peek }

        let isNewTabModified = switch peekModifier {
        case .option: isCommandModified
        case .command: isOptionModified
        }
        return isNewTabModified ? .newTab : .navigate
    }
}
