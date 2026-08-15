import Foundation

enum FirefoxTabSessionAdapter {
    static func decode(
        _ source: Data,
        importedAt: Date
    ) throws -> [BrowserTabSessionDraft] {
        let data = try MozillaLZ4.decompressedData(source)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BrowserTabMigrationError.invalidContents
        }
        guard let root = object as? [String: Any],
            let rawWindows = root["windows"] as? [Any],
            rawWindows.count <= BrowserPortableArchive.maximumSpaceCount
        else {
            throw BrowserTabMigrationError.invalidContents
        }
        var drafts = try rawWindows.enumerated().compactMap { ordinalIndex, raw -> BrowserTabSessionDraft? in
            guard let window = raw as? [String: Any],
                let rawTabs = window["tabs"] as? [Any]
            else { return nil }
            guard rawTabs.count <= BrowserTabMigration.maximumTabCountPerSpace else {
                throw BrowserTabMigrationError.resourceLimitExceeded
            }
            let decoded = rawTabs.enumerated().compactMap {
                sourceIndex,
                rawTab -> (sourceIndex: Int, tab: BrowserTabSessionTabDraft)? in
                guard let tab = rawTab as? [String: Any],
                    let entries = tab["entries"] as? [Any],
                    !entries.isEmpty
                else { return nil }
                let selectedEntryIndex = max(
                    0,
                    ((tab["index"] as? NSNumber)?.intValue ?? 1) - 1
                )
                let entryIndex = min(selectedEntryIndex, entries.count - 1)
                guard let entry = entries[entryIndex] as? [String: Any],
                    let urlString = entry["url"] as? String,
                    let url = BrowserTabMigrationSanitizer.url(urlString)
                else { return nil }
                let rawLastAccessed = (tab["lastAccessed"] as? NSNumber)?.doubleValue
                let lastActivatedAt =
                    rawLastAccessed.map {
                        Date(timeIntervalSince1970: $0 / 1_000)
                    } ?? importedAt
                return (
                    sourceIndex: sourceIndex,
                    tab: BrowserTabSessionTabDraft(
                        title: entry["title"] as? String ?? "",
                        url: url,
                        isPinned: (tab["pinned"] as? NSNumber)?.boolValue ?? false,
                        lastActivatedAt: lastActivatedAt
                    )
                )
            }
            let selectedSourceIndex = max(
                0,
                ((window["selected"] as? NSNumber)?.intValue ?? 1) - 1
            )
            return BrowserTabSessionDraft(
                sourceOrdinal: ordinalIndex + 1,
                name: window["title"] as? String,
                tabs: decoded.map(\.tab),
                selectedTabIndex: decoded.firstIndex { $0.sourceIndex >= selectedSourceIndex }
                    ?? decoded.indices.last
            )
        }
        let selectedWindowOrdinal = max(
            1,
            (root["selectedWindow"] as? NSNumber)?.intValue ?? 1
        )
        if let selectedWindowIndex = drafts.firstIndex(where: {
            $0.sourceOrdinal == selectedWindowOrdinal
        }), selectedWindowIndex != 0 {
            let selected = drafts.remove(at: selectedWindowIndex)
            drafts.insert(selected, at: 0)
        }
        return drafts
    }

}
