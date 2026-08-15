import Foundation

extension TabArchiveReason {
    var utilityTitle: LocalizedStringResource {
        switch self {
        case .autoCleanup: "Automatically cleaned"
        case .closed: "Closed"
        case .quickWindow: "Quick Window"
        }
    }
}
