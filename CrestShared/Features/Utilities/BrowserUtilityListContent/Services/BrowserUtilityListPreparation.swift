import Foundation

enum BrowserUtilityListPreparation {
    static let searchDebounce = Duration.milliseconds(60)

    nonisolated static func nextRefreshDate(
        for request: BrowserUtilityListRequest,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let itemDates = baseItems(for: request).map(\.date)
        guard !itemDates.isEmpty else { return nil }

        var deadlines: [Date] = []
        let startOfToday = calendar.startOfDay(for: now)
        if let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfToday
        ) {
            deadlines.append(nextDay)
        }

        switch request.filter.normalized(for: request.surface) {
        case .historyPastWeek:
            deadlines += request.history.compactMap {
                calendar.date(
                    byAdding: .day,
                    value: 7,
                    to: $0.lastVisitedAt
                )
            }
        case .historyPastMonth:
            deadlines += request.history.compactMap {
                calendar.date(
                    byAdding: .month,
                    value: 1,
                    to: $0.lastVisitedAt
                )
            }
        default:
            break
        }

        return deadlines.filter { $0 > now }.min()
    }

    nonisolated static func sections(
        for request: BrowserUtilityListRequest,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [BrowserUtilityListSection] {
        let query = request.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [BrowserUtilityListItem] = []
        for item in baseItems(for: request) {
            guard !Task.isCancelled else { return [] }
            guard matchesSearch(item, query: query),
                matchesFilter(
                    item,
                    request: request,
                    now: now,
                    calendar: calendar
                )
            else { continue }
            items.append(item)
        }
        guard !Task.isCancelled else { return [] }
        items.sort { $0.date > $1.date }
        guard !Task.isCancelled else { return [] }

        var timeframes: [BrowserUtilityTimeSection] = []
        var grouped: [BrowserUtilityTimeSection: [BrowserUtilityListItem]] = [:]
        for item in items {
            guard !Task.isCancelled else { return [] }
            let timeframe = BrowserUtilityTimeSection(
                date: item.date,
                now: now,
                calendar: calendar
            )
            if grouped[timeframe] == nil {
                timeframes.append(timeframe)
            }
            grouped[timeframe, default: []].append(item)
        }
        return timeframes.map { timeframe in
            BrowserUtilityListSection(
                timeframe: timeframe,
                items: grouped[timeframe, default: []]
            )
        }
    }

    nonisolated private static func baseItems(
        for request: BrowserUtilityListRequest
    ) -> [BrowserUtilityListItem] {
        switch request.surface {
        case .archive:
            request.archivedTabs
                .filter { !$0.tab.isStartPage }
                .map(BrowserUtilityListItem.archive)
        case .history:
            request.history.map(BrowserUtilityListItem.history)
        case .downloads:
            request.downloads.map(BrowserUtilityListItem.download)
        }
    }

    nonisolated private static func matchesSearch(
        _ item: BrowserUtilityListItem,
        query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        switch item {
        case .archive(let archived):
            return archived.tab.displayTitle.localizedStandardContains(query)
                || archived.tab.url?.absoluteString.localizedStandardContains(query) == true
        case .history(let entry):
            return entry.title.localizedStandardContains(query)
                || entry.url.absoluteString.localizedStandardContains(query)
        case .download(let download):
            return download.filename.localizedStandardContains(query)
                || download.state.utilityStatusText
                    .resolvedForSearch()
                    .localizedStandardContains(query)
        }
    }

    nonisolated private static func matchesFilter(
        _ item: BrowserUtilityListItem,
        request: BrowserUtilityListRequest,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let activeFilter = request.filter.normalized(for: request.surface)
        return switch (activeFilter, item) {
        case (.all, _):
            true
        case (.archivedClosed, let .archive(item)):
            item.reason == .closed || item.reason == .deleted
        case (.archivedAutomatically, let .archive(item)):
            item.reason == .autoCleanup
        case (.archivedSynced, let .archive(item)):
            item.reason == .synced || item.reason == .deletedOnAnotherDevice
        case (.archivedQuickWindow, let .archive(item)):
            item.reason == .quickWindow
        case (.historyToday, let .history(item)):
            calendar.isDate(item.lastVisitedAt, inSameDayAs: now)
        case (.historyPastWeek, let .history(item)):
            item.lastVisitedAt >= calendar.date(
                byAdding: .day,
                value: -7,
                to: now
            ) ?? .distantPast
        case (.historyPastMonth, let .history(item)):
            item.lastVisitedAt >= calendar.date(
                byAdding: .month,
                value: -1,
                to: now
            ) ?? .distantPast
        case (.downloadsInProgress, let .download(item)):
            item.state.isInProgress
        case (.downloadsFinished, let .download(item)):
            item.state == .finished
        case (.downloadsNeedsAttention, let .download(item)):
            item.state.needsAttention
        default:
            false
        }
    }
}
