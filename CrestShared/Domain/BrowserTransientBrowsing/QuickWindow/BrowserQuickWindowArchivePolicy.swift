import Foundation

enum BrowserQuickWindowArchivePolicy: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case after1Hour
    case after6Hours
    case after12Hours
    case after24Hours
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .after1Hour: "After 1 Hour"
        case .after6Hours: "After 6 Hours"
        case .after12Hours: "After 12 Hours"
        case .after24Hours: "After 24 Hours"
        case .never: "Never"
        }
    }

    var lifetime: TimeInterval? {
        switch self {
        case .after1Hour: 60 * 60
        case .after6Hours: 6 * 60 * 60
        case .after12Hours: 12 * 60 * 60
        case .after24Hours: 24 * 60 * 60
        case .never: nil
        }
    }
}
