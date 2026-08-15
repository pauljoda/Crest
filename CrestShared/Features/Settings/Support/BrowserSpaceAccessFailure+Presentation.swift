import SwiftUI

extension BrowserSpaceAccessFailure {
    var message: LocalizedStringResource {
        switch self {
        case .authenticationDenied:
            "The Space remains locked."
        case .authenticationUnavailable:
            "Device authentication isn’t available right now."
        }
    }
}
