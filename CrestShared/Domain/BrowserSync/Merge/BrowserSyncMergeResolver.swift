import Foundation

enum BrowserSyncMergeResolver {
    static func resolve(
        _ first: BrowserSyncRecord,
        _ second: BrowserSyncRecord
    ) throws -> BrowserSyncRecord {
        return try BrowserCoreSync.resolve(first, second)
    }

    private static func latestSavedTabsDisclosure(
        _ first: BrowserSyncSpace,
        _ second: BrowserSyncSpace
    ) -> BrowserSyncSpace? {
        switch (
            first.savedTabsExpansionModifiedAt,
            second.savedTabsExpansionModifiedAt
        ) {
        case (let firstDate?, let secondDate?) where firstDate != secondDate:
            firstDate > secondDate ? first : second
        case (_?, nil):
            first
        case (nil, _?):
            second
        default:
            nil
        }
    }

    /// Preserves the field when an older client writes a newer Space record,
    /// while letting an explicit empty array from a capable client clear it.
    /// When two capable devices both edit the same group, membership follows
    /// the newer Space record and each retained group's fields merge by their
    /// own wall-clock stamps.
    private static func mergedSplitGroups(
        _ first: [BrowserSplitGroupMetadata]?,
        _ second: [BrowserSplitGroupMetadata]?,
        prefersFirst: Bool
    ) -> [BrowserSplitGroupMetadata]? {
        switch (first, second) {
        case (nil, nil):
            return nil
        case (let groups?, nil), (nil, let groups?):
            return groups
        case (let first?, let second?):
            let preferred = prefersFirst ? first : second
            let fallback = prefersFirst ? second : first
            let fallbackByID = Dictionary(
                uniqueKeysWithValues: fallback.map { ($0.id, $0) }
            )
            return preferred.map { metadata in
                guard let older = fallbackByID[metadata.id] else {
                    return metadata
                }
                return BrowserSplitGroupMetadata.merged(
                    preferred: metadata,
                    fallback: older
                )
            }
        }
    }

    private static func latestFolderDisclosure(
        _ first: BrowserSyncFolder,
        _ second: BrowserSyncFolder
    ) -> BrowserSyncFolder? {
        switch (first.collapseModifiedAt, second.collapseModifiedAt) {
        case (let firstDate?, let secondDate?) where firstDate != secondDate:
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
        case (let firstDate?, let secondDate?) where firstDate != secondDate:
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
        case (let firstDate?, let secondDate?) where firstDate != secondDate:
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
