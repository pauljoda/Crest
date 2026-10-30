import Foundation

/// The outcome the helper reports inside a decrypted reply. Each instance
/// knows what it means for the caller, and a number Crest does not know fails
/// closed as an error.
struct ApplePasswordsQueryStatus: Hashable, Sendable {
    // MARK: - Static Variables

    static let success = ApplePasswordsQueryStatus(number: 0, meaning: .answered)
    static let genericError = ApplePasswordsQueryStatus(number: 1, meaning: .failed)
    static let invalidParameter = ApplePasswordsQueryStatus(number: 2, meaning: .failed)
    static let noResults = ApplePasswordsQueryStatus(number: 3, meaning: .empty)
    static let failedToDelete = ApplePasswordsQueryStatus(number: 4, meaning: .failed)
    static let failedToUpdate = ApplePasswordsQueryStatus(number: 5, meaning: .failed)
    static let invalidMessageFormat = ApplePasswordsQueryStatus(number: 6, meaning: .failed)
    static let duplicateItem = ApplePasswordsQueryStatus(number: 7, meaning: .failed)
    static let unknownAction = ApplePasswordsQueryStatus(number: 8, meaning: .failed)
    /// The helper no longer knows the session, so Crest must pair again.
    static let invalidSession = ApplePasswordsQueryStatus(number: 9, meaning: .sessionLost)

    static let all: [ApplePasswordsQueryStatus] = [
        success, genericError, invalidParameter, noResults, failedToDelete, failedToUpdate, invalidMessageFormat,
        duplicateItem, unknownAction, invalidSession,
    ]

    // MARK: - Types

    enum Meaning: Sendable {
        case answered
        case empty
        case failed
        case sessionLost
    }

    // MARK: - Variables

    let number: Int
    let meaning: Meaning

    // MARK: - Initializers

    private init(number: Int, meaning: Meaning) {
        self.number = number
        self.meaning = meaning
    }

    // MARK: - Actions - Lookup

    /// The status a number names. A number Crest does not know is a failure,
    /// kept as it is so the log can name it.
    static func numbered(_ number: Int) -> ApplePasswordsQueryStatus {
        all.first { $0.number == number } ?? ApplePasswordsQueryStatus(number: number, meaning: .failed)
    }

    // MARK: - Actions - Interpreting

    /// Throws unless the reply carries an answer or an empty result.
    /// - Returns: Whether the helper answered; false means it found nothing.
    func requireAnswer() throws -> Bool {
        switch meaning {
        case .answered: return true
        case .empty: return false
        case .failed: throw ApplePasswordsError.queryFailed(self)
        case .sessionLost: throw ApplePasswordsError.notPaired
        }
    }
}
