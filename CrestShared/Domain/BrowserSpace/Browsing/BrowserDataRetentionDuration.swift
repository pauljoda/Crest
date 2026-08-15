import Foundation

enum BrowserDataRetentionDuration: String, Codable, CaseIterable, Equatable,
    Identifiable, Sendable
{
    case oneDay
    case oneWeek
    case thirtyDays
    case ninetyDays
    case oneYear
    case forever

    var id: Self { self }

    var lifetime: TimeInterval? {
        let day: TimeInterval = 24 * 60 * 60
        return switch self {
        case .oneDay: day
        case .oneWeek: 7 * day
        case .thirtyDays: 30 * day
        case .ninetyDays: 90 * day
        case .oneYear: 365 * day
        case .forever: nil
        }
    }
}
