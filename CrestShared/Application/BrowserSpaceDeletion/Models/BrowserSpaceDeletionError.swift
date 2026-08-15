import Foundation

enum BrowserSpaceDeletionError: LocalizedError, Equatable {
    case missingSpace
    case cannotDeleteLastSpace
    case alreadyDeleting
    case spaceChangedDuringDeletion

    var errorDescription: String? {
        switch self {
        case .missingSpace:
            "That Space no longer exists."
        case .cannotDeleteLastSpace:
            "Crest needs at least one Space."
        case .alreadyDeleting:
            "Crest is already deleting that Space."
        case .spaceChangedDuringDeletion:
            "The Space changed while Crest was deleting its data. No Space record was removed."
        }
    }
}
