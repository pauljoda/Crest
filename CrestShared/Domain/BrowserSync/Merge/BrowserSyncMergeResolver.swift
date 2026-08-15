import Foundation

enum BrowserSyncMergeResolver {
    static func resolve(
        _ first: BrowserSyncRecord,
        _ second: BrowserSyncRecord
    ) throws -> BrowserSyncRecord {
        if first.tombstone?.reason == .explicitDelete {
            return first
        }
        if second.tombstone?.reason == .explicitDelete {
            return second
        }

        if let tombstone = first.tombstone,
           case let .tab(tab)? = second.payload,
           tab.lastActivatedAt > tombstone.deletedAt {
            return second
        }
        if let tombstone = second.tombstone,
           case let .tab(tab)? = first.payload,
           tab.lastActivatedAt > tombstone.deletedAt {
            return first
        }

        let newer = first.version < second.version ? second : first
        guard let firstPayload = first.payload, let secondPayload = second.payload else {
            return newer
        }

        switch (firstPayload, secondPayload) {
        case let (.space(firstSpace), .space(secondSpace)):
            var merged = newer.payload?.spaceValue ?? firstSpace
            if let latestDisclosure = latestSavedTabsDisclosure(
                firstSpace,
                secondSpace
            ) {
                merged.isSavedTabsExpanded = latestDisclosure.isSavedTabsExpanded
                merged.savedTabsExpansionModifiedAt = latestDisclosure
                    .savedTabsExpansionModifiedAt
            }
            return BrowserSyncRecord.save(.space(merged), version: newer.version)
        case let (.folder(firstFolder), .folder(secondFolder)):
            var merged = newer.payload?.folderValue ?? firstFolder
            if let latestDisclosure = latestFolderDisclosure(
                firstFolder,
                secondFolder
            ) {
                merged.isCollapsed = latestDisclosure.isCollapsed
                merged.collapseModifiedAt = latestDisclosure.collapseModifiedAt
            }
            return BrowserSyncRecord.save(.folder(merged), version: newer.version)
        case let (.tab(firstTab), .tab(secondTab)):
            var merged = newer.payload?.tabValue ?? firstTab
            merged.lastActivatedAt = max(firstTab.lastActivatedAt, secondTab.lastActivatedAt)
            if let latestPosition = latestPosition(firstTab, secondTab) {
                merged.placement = latestPosition.placement
                merged.folderID = latestPosition.placement == .saved
                    ? latestPosition.folderID
                    : nil
                merged.orderToken = latestPosition.orderToken
                merged.positionModifiedAt = latestPosition.positionModifiedAt
                // Split membership rides the position win-set rather than a
                // timestamp of its own, because every group mutation is a move:
                // joining, leaving, or dissolving a split marks
                // `positionModifiedAt` on each affected member. That is what
                // protects membership from a device that has never heard of
                // splits — re-saving a tab it merely activated leaves
                // `positionModifiedAt` untouched, so the group-aware record
                // still owns the position and wins the field back. A device
                // that genuinely *moves* a grouped tab does take the position,
                // and dropping membership there is correct: moving a member out
                // of its run is an ungroup either way.
                //
                // Taken only in the winner's own placement context, exactly as
                // `folderID` is above: a pinned tab is never a member, so a
                // winner that pinned the tab hands back no membership at all.
                merged.splitGroupID =
                    BrowserSplitGroupPolicy.allowsMembership(
                        placement: latestPosition.placement
                    )
                    ? latestPosition.splitGroupID
                    : nil
                // Upgrade path, deliberately not built yet: a dedicated
                // `splitGroupModifiedAt` plus a `latestSplitGroup()` resolver
                // mirroring `titleModifiedAt` would separate membership from
                // position entirely. It is only worth its record-size and
                // migration cost once membership can change without a move.
            } else {
                merged.placement = TabPlacement.max(
                    firstTab.placement,
                    secondTab.placement
                )
                if merged.placement != .saved {
                    merged.folderID = nil
                } else if merged.folderID == nil {
                    merged.folderID = firstTab.folderID ?? secondTab.folderID
                }
                // Neither side claims a position, so neither can claim to have
                // cleared membership either. Same nil-fallback as `folderID`:
                // whichever copy knows the group keeps it.
                if merged.splitGroupID == nil {
                    merged.splitGroupID = firstTab.splitGroupID ?? secondTab.splitGroupID
                }
            }
            if let latestTitle = latestTitle(firstTab, secondTab) {
                merged.customTitle = latestTitle.customTitle
                merged.titleModifiedAt = latestTitle.titleModifiedAt
            }
            return BrowserSyncRecord.save(.tab(merged), version: newer.version)
        case let (.history(firstHistory), .history(secondHistory)):
            var merged = newer.payload?.historyValue ?? firstHistory
            merged = BrowserSyncHistory(
                id: merged.id,
                spaceID: merged.spaceID,
                url: merged.url,
                title: merged.title,
                firstVisitedAt: min(firstHistory.firstVisitedAt, secondHistory.firstVisitedAt),
                lastVisitedAt: max(firstHistory.lastVisitedAt, secondHistory.lastVisitedAt),
                visitCount: max(firstHistory.visitCount, secondHistory.visitCount)
            )
            return BrowserSyncRecord.save(.history(merged), version: newer.version)
        default:
            return newer
        }
    }

    private static func latestSavedTabsDisclosure(
        _ first: BrowserSyncSpace,
        _ second: BrowserSyncSpace
    ) -> BrowserSyncSpace? {
        switch (
            first.savedTabsExpansionModifiedAt,
            second.savedTabsExpansionModifiedAt
        ) {
        case let (firstDate?, secondDate?) where firstDate != secondDate:
            firstDate > secondDate ? first : second
        case (_?, nil):
            first
        case (nil, _?):
            second
        default:
            nil
        }
    }

    private static func latestFolderDisclosure(
        _ first: BrowserSyncFolder,
        _ second: BrowserSyncFolder
    ) -> BrowserSyncFolder? {
        switch (first.collapseModifiedAt, second.collapseModifiedAt) {
        case let (firstDate?, secondDate?) where firstDate != secondDate:
            firstDate > secondDate ? first : second
        case (_?, nil):
            first
        case (nil, _?):
            second
        default:
            nil
        }
    }

    private static func latestPosition(
        _ first: BrowserSyncTab,
        _ second: BrowserSyncTab
    ) -> BrowserSyncTab? {
        switch (first.positionModifiedAt, second.positionModifiedAt) {
        case let (firstDate?, secondDate?) where firstDate != secondDate:
            firstDate > secondDate ? first : second
        case (_?, nil):
            first
        case (nil, _?):
            second
        default:
            nil
        }
    }

    private static func latestTitle(
        _ first: BrowserSyncTab,
        _ second: BrowserSyncTab
    ) -> BrowserSyncTab? {
        switch (first.titleModifiedAt, second.titleModifiedAt) {
        case let (firstDate?, secondDate?) where firstDate != secondDate:
            firstDate > secondDate ? first : second
        case (_?, nil):
            first
        case (nil, _?):
            second
        default:
            nil
        }
    }
}
