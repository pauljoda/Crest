import Foundation

extension BrowserExtensionAccessDecision {
    var title: LocalizedStringResource {
        switch self {
        case .ask:
            "Ask"
        case .allow:
            "Allow"
        case .block:
            "Block"
        }
    }
}
