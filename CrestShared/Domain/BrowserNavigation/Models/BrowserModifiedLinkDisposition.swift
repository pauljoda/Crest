import Foundation

enum BrowserModifiedLinkDisposition: Equatable, Sendable {
    case navigate
    case backgroundTab(URL)
    case foregroundTab(URL)

    static func classify(
        destinationURL: URL?,
        isUserActivatedLink: Bool,
        isCommandModified: Bool,
        isShiftModified: Bool,
        isMiddleClick: Bool
    ) -> BrowserModifiedLinkDisposition {
        guard isUserActivatedLink,
            isCommandModified || isMiddleClick,
            let destinationURL,
            BrowserExternalURLPolicy.accepts(destinationURL)
        else {
            return .navigate
        }
        return isShiftModified
            ? .foregroundTab(destinationURL)
            : .backgroundTab(destinationURL)
    }
}
