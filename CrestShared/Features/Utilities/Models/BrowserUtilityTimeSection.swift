import Foundation

struct BrowserUtilityTimeSection: Hashable, Identifiable, Sendable {
    let id: String
    let sortDate: Date

    private let period: BrowserUtilityTimePeriod

    var title: LocalizedStringResource {
        switch period {
        case .today:
            "Today"
        case let .daysAgo(count):
            "\(count) days ago"
        case let .weeksAgo(count):
            "\(count) weeks ago"
        case let .month(date):
            "\(date, format: .dateTime.month(.wide).year())"
        }
    }

    init(
        date: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let today = calendar.startOfDay(for: now)
        let itemDay = calendar.startOfDay(for: min(date, now))
        let daysAgo = max(
            calendar.dateComponents([.day], from: itemDay, to: today).day ?? 0,
            0
        )

        if daysAgo < 7 {
            sortDate = itemDay
            id = "day-\(itemDay.timeIntervalSinceReferenceDate)"
            period = daysAgo == 0 ? .today : .daysAgo(daysAgo)
            return
        }

        if daysAgo < 42 {
            let weeksAgo = max(daysAgo / 7, 1)
            sortDate = calendar.date(
                byAdding: .day,
                value: -(weeksAgo * 7),
                to: today
            ) ?? itemDay
            id = "week-\(weeksAgo)"
            period = .weeksAgo(weeksAgo)
            return
        }

        let monthStart = calendar.dateInterval(
            of: .month,
            for: itemDay
        )?.start ?? itemDay
        sortDate = monthStart
        id = "month-\(monthStart.timeIntervalSinceReferenceDate)"
        period = .month(itemDay)
    }
}
