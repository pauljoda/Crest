import Foundation

enum BrowserCurrentTabCleanupPolicy: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case after12Hours
    case after24Hours
    case after7Days
    case after30Days
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .after12Hours: "After 12 Hours"
        case .after24Hours: "After 24 Hours"
        case .after7Days: "After 7 Days"
        case .after30Days: "After 30 Days"
        case .never: "Never"
        }
    }

    var lifetime: TimeInterval? {
        switch self {
        case .after12Hours: 12 * 60 * 60
        case .after24Hours: 24 * 60 * 60
        case .after7Days: 7 * 24 * 60 * 60
        case .after30Days: 30 * 24 * 60 * 60
        case .never: nil
        }
    }
}
