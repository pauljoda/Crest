import Foundation

enum BrowserCredentialSavePlan: Equatable, Sendable {
    case create
    case update(CredentialDescriptor)
    case alreadyStored(CredentialDescriptor)

    var requiresConfirmation: Bool {
        switch self {
        case .create, .update:
            true
        case .alreadyStored:
            false
        }
    }

    var isUpdate: Bool {
        if case .update = self {
            return true
        }
        return false
    }
}
