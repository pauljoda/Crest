import Foundation

enum BrowserUtilityListReconciliation {
    nonisolated static func sections(
        preparedSections: [BrowserUtilityListSection],
        surface: BrowserUtilitySurface,
        assignment: BrowserSpaceRuntimeAssignment,
        downloads: [BrowserDownloadItem],
        searchText: String,
        filter: BrowserUtilityListFilter
    ) -> [BrowserUtilityListSection] {
        guard surface == .downloads else { return preparedSections }

        let liveDownloads = downloads.reduce(
            into: [UUID: BrowserDownloadItem]()
        ) { result, item in
            guard item.profileID == assignment.profileID else { return }
            result[item.id] = item
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeFilter = filter.normalized(for: .downloads)
        var emittedDownloadIDs: Set<UUID> = []

        return preparedSections.compactMap { section in
            let items: [BrowserUtilityListItem] = section.items.compactMap {
                item -> BrowserUtilityListItem? in
                guard case .download(let preparedDownload) = item,
                    emittedDownloadIDs.insert(preparedDownload.id).inserted,
                    let currentDownload = liveDownloads[preparedDownload.id],
                    matchesSearch(currentDownload, query: query),
                    matchesFilter(currentDownload, filter: activeFilter)
                else { return nil }
                return BrowserUtilityListItem.download(currentDownload)
            }
            guard !items.isEmpty else { return nil }
            return BrowserUtilityListSection(
                timeframe: section.timeframe,
                items: items
            )
        }
    }

    nonisolated private static func matchesSearch(
        _ item: BrowserDownloadItem,
        query: String
    ) -> Bool {
        query.isEmpty
            || item.filename.localizedStandardContains(query)
            || item.state.utilityStatusText
                .resolvedForSearch()
                .localizedStandardContains(query)
    }

    nonisolated private static func matchesFilter(
        _ item: BrowserDownloadItem,
        filter: BrowserUtilityListFilter
    ) -> Bool {
        switch filter {
        case .all:
            true
        case .downloadsInProgress:
            item.state.isInProgress
        case .downloadsFinished:
            item.state == .finished
        case .downloadsNeedsAttention:
            item.state.needsAttention
        default:
            false
        }
    }
}
