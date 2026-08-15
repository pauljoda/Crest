import Foundation
import Observation

enum BrowserCredentialSuggestionPhase: Equatable, Sendable {
    case idle
    case loading
    case empty
    case suggestions([CredentialDescriptor])
    case failed
}
