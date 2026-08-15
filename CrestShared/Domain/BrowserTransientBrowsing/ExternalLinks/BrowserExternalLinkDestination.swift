import Foundation

enum BrowserExternalLinkDestination: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case quickWindow
    case mostRecentSpace
    case chosenSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickWindow: "Quick Window"
        case .mostRecentSpace: "Most Recent Space"
        case .chosenSpace: "Chosen Space"
        }
    }
}
