import Foundation

enum BrowserUtilityTimePeriod: Hashable, Sendable {
    case today
    case daysAgo(Int)
    case weeksAgo(Int)
    case month(Date)
}
