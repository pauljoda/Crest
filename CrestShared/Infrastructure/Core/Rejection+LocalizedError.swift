import Foundation

/// A rejection reads as what its rule tells the person, where the rule says
/// anything, so an error view shows the core's refusal in the same words.
extension Rejection: LocalizedError {
    var errorDescription: String? {
        message.map { String(localized: $0) }
    }
}
