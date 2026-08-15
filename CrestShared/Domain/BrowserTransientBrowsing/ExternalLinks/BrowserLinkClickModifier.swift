import Foundation

enum BrowserLinkClickModifier: String, Codable, CaseIterable, Equatable, Sendable {
    case option
    case command

    var title: String {
        switch self {
        case .option: "Option (⌥)"
        case .command: "Command (⌘)"
        }
    }

    var clickTitle: String {
        switch self {
        case .option: "Option-click"
        case .command: "Command-click"
        }
    }
}
