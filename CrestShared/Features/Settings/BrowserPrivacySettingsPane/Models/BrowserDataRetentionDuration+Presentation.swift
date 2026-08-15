import Foundation

extension BrowserDataRetentionDuration {
    var title: String {
        switch self {
        case .oneDay: "1 Day"
        case .oneWeek: "1 Week"
        case .thirtyDays: "30 Days"
        case .ninetyDays: "90 Days"
        case .oneYear: "1 Year"
        case .forever: "Forever"
        }
    }
}
