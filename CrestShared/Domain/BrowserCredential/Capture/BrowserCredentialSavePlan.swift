import Foundation

/// The core's save plan for one candidate, carrying the descriptor it names.
enum BrowserCredentialSavePlan: Equatable, Sendable {
    case create
    case update(CredentialDescriptor)
    case alreadyStored(CredentialDescriptor)
}
