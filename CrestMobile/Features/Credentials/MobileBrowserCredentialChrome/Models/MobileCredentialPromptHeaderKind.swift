import SwiftUI

enum MobileCredentialPromptHeaderKind {
    case strongPassword
    case suggestions

    var symbol: String {
        switch self {
        case .strongPassword: "key.horizontal.fill"
        case .suggestions: "key.fill"
        }
    }

    func title(spaceName: String) -> LocalizedStringKey {
        switch self {
        case .strongPassword: "Strong Password for \(spaceName)"
        case .suggestions: "Passwords in \(spaceName)"
        }
    }
}
