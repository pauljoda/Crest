import Foundation

enum BrowserContentBlockingPolicy: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case balanced
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .off: "Off"
        }
    }
}
