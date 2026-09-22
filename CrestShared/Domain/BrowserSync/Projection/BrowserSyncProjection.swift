import Foundation

enum BrowserSyncProjection {
    static func payloads(
        from session: BrowserSession,
        preferences: BrowserSyncPreferences,
        existingRecords: [BrowserSyncRecord]
    ) throws -> [BrowserSyncPayload] {
        return try BrowserCoreSync.project(session, preferences: preferences, records: existingRecords)
    }

    private static func requiredOrderToken(
        for recordID: BrowserSyncRecordID,
        in tokens: [BrowserSyncRecordID: String]
    ) throws -> String {
        guard let token = tokens[recordID] else {
            throw BrowserSyncError.invalidRecord(recordID.recordName)
        }
        return token
    }

    private static func existingOrderTokens(
        from records: [BrowserSyncRecord]
    ) -> [BrowserSyncRecordID: String] {
        Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                switch record.payload {
                case .space(let space):
                    (record.id, space.orderToken)
                case .folder(let folder):
                    (record.id, folder.orderToken)
                case .tab(let tab):
                    (record.id, tab.orderToken)
                case .archive(let archive):
                    (record.id, archive.tab.orderToken)
                case .history, .none:
                    nil
                }
            })
    }
}

/// Only portable web pages enter sync. Native documents and device-specific
/// schemes remain in the local session, including when remote changes arrive.
enum BrowserSyncContentPolicy {
    static func includes(_ url: URL?) -> Bool {
        guard let url, let host = url.host, !host.isEmpty else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    static func includes(_ tab: BrowserTab) -> Bool {
        tab.nativeContent == nil && includes(tab.url)
            && (tab.savedSiteURL == nil || includes(tab.savedSiteURL))
    }

    static func includes(_ tab: BrowserSyncTab) -> Bool {
        tab.nativeContent == nil && includes(tab.url)
            && (tab.savedURL == nil || includes(tab.savedURL))
    }

    static func includes(_ payload: BrowserSyncPayload) -> Bool {
        switch payload {
        case .space, .folder: true
        case .tab(let tab): includes(tab)
        case .archive(let archive): includes(archive.tab)
        case .history(let history): includes(history.url)
        }
    }
}
