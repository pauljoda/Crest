import Foundation

enum SafariTabSessionAdapter {
    private static let windowKeys = [
        "Windows", "SessionWindows", "BrowserWindows", "OrderedWindows",
    ]
    private static let tabKeys = [
        "Tabs", "SessionTabs", "TabStates", "OrderedTabs", "Children",
    ]
    private static let urlKeys = [
        "URL", "URLString", "TabURL", "CurrentURL", "SessionTabURL", "url",
    ]
    private static let titleKeys = [
        "Title", "TabTitle", "PageTitle", "title",
    ]

    static func decode(
        _ data: Data,
        importedAt: Date
    ) throws -> [BrowserTabSessionDraft] {
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            throw BrowserTabMigrationError.invalidContents
        }
        let root = propertyList as? [String: Any]
        let rawWindows =
            root.flatMap { array(in: $0, keys: windowKeys) }
            ?? (propertyList as? [Any])
        if let rawWindows {
            let drafts = try rawWindows.enumerated().compactMap { index, raw -> BrowserTabSessionDraft? in
                guard let window = raw as? [String: Any] else { return nil }
                return try decodeWindow(window, ordinal: index + 1, importedAt: importedAt)
            }
            return reordered(
                drafts,
                selectedOneBasedIndex: integer(
                    in: root,
                    keys: [
                        "SelectedWindowIndex", "SelectedWindow", "selectedWindow",
                    ])
            )
        }

        var rawTabs: [(Int, [String: Any])] = []
        collectTabDictionaries(
            in: propertyList,
            depth: 0,
            rawTabs: &rawTabs
        )
        let tabs = try rawTabs.compactMap { sourceIndex, dictionary in
            try decodeTab(dictionary, sourceIndex: sourceIndex, importedAt: importedAt)
        }
        return [
            BrowserTabSessionDraft(
                sourceOrdinal: 1,
                name: root.flatMap { string(in: $0, keys: ["Title", "Name"]) },
                tabs: tabs.map(\.tab),
                selectedTabIndex: 0
            )
        ]
    }

    private static func decodeWindow(
        _ window: [String: Any],
        ordinal: Int,
        importedAt: Date
    ) throws -> BrowserTabSessionDraft {
        let rawTabs = array(in: window, keys: tabKeys) ?? []
        guard rawTabs.count <= BrowserTabMigration.maximumTabCountPerSpace else {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }
        let decoded = try rawTabs.enumerated().compactMap {
            sourceIndex,
            raw -> (sourceIndex: Int, tab: BrowserTabSessionTabDraft)? in
            guard let dictionary = raw as? [String: Any] else { return nil }
            return try decodeTab(
                dictionary,
                sourceIndex: sourceIndex,
                importedAt: importedAt
            )
        }
        let sourceSelection =
            integer(
                in: window,
                keys: [
                    "SelectedTabIndex", "SelectedTab", "selected",
                ]) ?? 0
        return BrowserTabSessionDraft(
            sourceOrdinal: ordinal,
            name: string(in: window, keys: ["Title", "Name", "WindowTitle"]),
            tabs: decoded.map(\.tab),
            selectedTabIndex: nearestIndex(
                to: sourceSelection,
                in: decoded.map(\.sourceIndex)
            )
        )
    }

    private static func decodeTab(
        _ source: [String: Any],
        sourceIndex: Int,
        importedAt: Date
    ) throws -> (sourceIndex: Int, tab: BrowserTabSessionTabDraft)? {
        let nested = nestedState(in: source)
        guard
            let urlString = string(in: source, keys: urlKeys)
                ?? nested.flatMap({ string(in: $0, keys: urlKeys) }),
            let url = BrowserTabMigrationSanitizer.url(urlString)
        else { return nil }
        let title =
            string(in: source, keys: titleKeys)
            ?? nested.flatMap { string(in: $0, keys: titleKeys) }
            ?? ""
        return (
            sourceIndex,
            BrowserTabSessionTabDraft(
                title: title,
                url: url,
                isPinned: boolean(in: source, keys: ["Pinned", "IsPinned", "pinned"]),
                lastActivatedAt: date(
                    in: source,
                    keys: ["LastActive", "LastAccessed", "DateVisited", "lastAccessed"],
                    fallback: importedAt
                )
            )
        )
    }

    private static func collectTabDictionaries(
        in value: Any,
        depth: Int,
        rawTabs: inout [(Int, [String: Any])]
    ) {
        guard depth < BrowserSpace.maximumFolderDepth,
            rawTabs.count < BrowserTabMigration.maximumTabCountPerSpace
        else { return }
        if let dictionary = value as? [String: Any] {
            if string(in: dictionary, keys: urlKeys) != nil {
                rawTabs.append((rawTabs.count, dictionary))
                return
            }
            for nestedValue in dictionary.values {
                collectTabDictionaries(
                    in: nestedValue,
                    depth: depth + 1,
                    rawTabs: &rawTabs
                )
            }
            return
        }
        guard let array = value as? [Any] else { return }
        for nestedValue in array {
            collectTabDictionaries(
                in: nestedValue,
                depth: depth + 1,
                rawTabs: &rawTabs
            )
        }
    }

    private static func nestedState(in source: [String: Any]) -> [String: Any]? {
        for key in ["TabState", "SessionState", "PageState", "URIDictionary"] {
            if let value = source[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private static func reordered(
        _ drafts: [BrowserTabSessionDraft],
        selectedOneBasedIndex: Int?
    ) -> [BrowserTabSessionDraft] {
        guard let selectedOneBasedIndex else { return drafts }
        let selectedOrdinal = selectedOneBasedIndex > 0 ? selectedOneBasedIndex : 1
        guard
            let selectedIndex = drafts.firstIndex(where: {
                $0.sourceOrdinal == selectedOrdinal
            }), selectedIndex != 0
        else { return drafts }
        var reordered = drafts
        let selected = reordered.remove(at: selectedIndex)
        reordered.insert(selected, at: 0)
        return reordered
    }

    private static func nearestIndex(to sourceIndex: Int, in indexes: [Int]) -> Int? {
        indexes.firstIndex(where: { $0 >= sourceIndex }) ?? indexes.indices.last
    }

    private static func array(
        in dictionary: [String: Any],
        keys: [String]
    ) -> [Any]? {
        keys.lazy.compactMap { dictionary[$0] as? [Any] }.first
    }

    private static func string(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        keys.lazy.compactMap { dictionary[$0] as? String }.first
    }

    private static func integer(
        in dictionary: [String: Any]?,
        keys: [String]
    ) -> Int? {
        guard let dictionary else { return nil }
        return keys.lazy.compactMap { (dictionary[$0] as? NSNumber)?.intValue }.first
    }

    private static func boolean(
        in dictionary: [String: Any],
        keys: [String]
    ) -> Bool {
        keys.lazy.compactMap { (dictionary[$0] as? NSNumber)?.boolValue }.first ?? false
    }

    private static func date(
        in dictionary: [String: Any],
        keys: [String],
        fallback: Date
    ) -> Date {
        for key in keys {
            if let date = dictionary[key] as? Date {
                return date
            }
            if let number = dictionary[key] as? NSNumber {
                let raw = number.doubleValue
                if raw > 10_000_000_000 {
                    return Date(timeIntervalSince1970: raw / 1_000)
                }
                return Date(timeIntervalSince1970: raw)
            }
        }
        return fallback
    }
}
