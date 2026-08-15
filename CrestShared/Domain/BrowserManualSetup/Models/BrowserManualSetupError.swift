import Foundation

enum BrowserManualSetupError: Error, Equatable, LocalizedError {
    case invalidAddress
    case missingSpace
    case pinnedLimitReached
    case spaceLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "Enter a website, URL, or search."
        case .missingSpace:
            "That Space is no longer available."
        case .pinnedLimitReached:
            "This Space already has the maximum of \(BrowserSpace.maximumPinnedTabs) pinned tabs."
        case .spaceLimitReached:
            "Crest supports up to \(BrowserPortableArchive.maximumSpaceCount) Spaces."
        }
    }
}
