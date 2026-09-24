import Foundation

enum BrowserSpaceDeletionError: LocalizedError, Equatable {
    case missingSpace
    case alreadyDeleting

    var errorDescription: String? {
        switch self {
        case .missingSpace:
            "That Space no longer exists."
        case .alreadyDeleting:
            "Crest is already deleting that Space."
        }
    }
}
