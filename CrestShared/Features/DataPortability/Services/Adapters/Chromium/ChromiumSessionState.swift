import Foundation

struct ChromiumSessionState {
    private let importedAt: Date
    private var tabs: [Int32: ChromiumSessionTab] = [:]
    private var windows: [Int32: ChromiumSessionWindow] = [:]
    private var closedTabIDs: Set<Int32> = []
    private var closedWindowIDs: Set<Int32> = []
    private var activeWindowID: Int32?
    private(set) var hasInitialStateMarker = false

    init(importedAt: Date) {
        self.importedAt = importedAt
    }

    mutating func apply(commandID: UInt8, payload: Data) throws {
        switch commandID {
        case 0:
            guard let windowID = payload.int32(at: 0),
                let tabID = payload.int32(at: 4)
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            mutateTab(tabID) { $0.windowID = windowID }
            ensureWindow(windowID)
        case 2:
            guard let tabID = payload.int32(at: 0),
                let index = payload.int32(at: 4)
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            mutateTab(tabID) { $0.visualIndex = Int(index) }
        case 5:
            guard let tabID = payload.int32(at: 0),
                let index = payload.int32(at: 4)
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            mutateTab(tabID) { tab in
                tab.navigations = tab.navigations.filter { $0.key < Int(index) }
            }
        case 6:
            try applyNavigation(payload)
        case 7:
            guard let tabID = payload.int32(at: 0),
                let index = payload.int32(at: 4)
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            mutateTab(tabID) { $0.selectedNavigationIndex = Int(index) }
        case 8:
            guard let windowID = payload.int32(at: 0),
                let index = payload.int32(at: 4)
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            mutateWindow(windowID) { $0.selectedVisualIndex = Int(index) }
        case 11:
            guard let tabID = payload.int32(at: 0),
                let index = payload.int32(at: 4)
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            guard index > 0 else { return }
            prune(tabID: tabID, index: 0, count: Int(index))
        case 12:
            guard let tabID = payload.int32(at: 0), payload.count >= 5 else {
                throw BrowserTabMigrationError.invalidContents
            }
            mutateTab(tabID) { $0.isPinned = payload[4] != 0 }
        case 16:
            guard let tabID = payload.int32(at: 0) else {
                throw BrowserTabMigrationError.invalidContents
            }
            tabs.removeValue(forKey: tabID)
            closedTabIDs.insert(tabID)
        case 17:
            guard let windowID = payload.int32(at: 0) else {
                throw BrowserTabMigrationError.invalidContents
            }
            windows.removeValue(forKey: windowID)
            closedWindowIDs.insert(windowID)
        case 20:
            guard let windowID = payload.int32(at: 0) else {
                throw BrowserTabMigrationError.invalidContents
            }
            activeWindowID = windowID
        case 21:
            guard let tabID = payload.int32(at: 0),
                let rawTime = payload.int64(at: 8)
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            let unixSeconds = Double(rawTime) / 1_000_000 - 11_644_473_600
            let date = Date(timeIntervalSince1970: unixSeconds)
            mutateTab(tabID) { $0.lastActivatedAt = date }
        case 24:
            guard let tabID = payload.int32(at: 0),
                let index = payload.int32(at: 4),
                let count = payload.int32(at: 8)
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            guard index >= 0, count > 0 else { return }
            prune(tabID: tabID, index: Int(index), count: Int(count))
        case 31:
            var pickle = try ChromiumPickleReader(payload)
            guard let windowID = pickle.readInt32(),
                let title = pickle.readString(maximumByteCount: 4_096)
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            mutateWindow(windowID) { $0.title = title }
        case 255:
            guard payload.isEmpty else {
                throw BrowserTabMigrationError.invalidContents
            }
            hasInitialStateMarker = true
        default:
            break
        }
    }

    func drafts() -> [BrowserTabSessionDraft] {
        let sortedWindowIDs = windows.keys
            .filter { !closedWindowIDs.contains($0) }
            .sorted()
        let ordinals = Dictionary(
            uniqueKeysWithValues: sortedWindowIDs.enumerated().map { ($0.element, $0.offset + 1) }
        )
        var drafts = sortedWindowIDs.compactMap { windowID -> BrowserTabSessionDraft? in
            guard let window = windows[windowID] else { return nil }
            let sourceTabs = tabs.compactMap {
                tabID,
                tab -> (Int32, ChromiumSessionTab)? in
                guard tab.windowID == windowID,
                    !closedTabIDs.contains(tabID)
                else { return nil }
                return (tabID, tab)
            }.sorted {
                if $0.1.visualIndex != $1.1.visualIndex {
                    return $0.1.visualIndex < $1.1.visualIndex
                }
                return $0.0 < $1.0
            }
            let decoded = sourceTabs.compactMap { _, tab -> (Int, BrowserTabSessionTabDraft)? in
                guard let navigation = selectedNavigation(for: tab) else { return nil }
                return (
                    tab.visualIndex,
                    BrowserTabSessionTabDraft(
                        title: navigation.title,
                        url: navigation.url,
                        isPinned: tab.isPinned,
                        lastActivatedAt: tab.lastActivatedAt
                    )
                )
            }
            guard !decoded.isEmpty else { return nil }
            let selectedIndex =
                decoded.firstIndex {
                    $0.0 >= window.selectedVisualIndex
                } ?? decoded.indices.last
            return BrowserTabSessionDraft(
                sourceOrdinal: ordinals[windowID] ?? 1,
                name: window.title,
                tabs: decoded.map(\.1),
                selectedTabIndex: selectedIndex
            )
        }
        if let activeWindowID,
            let activeIndex = drafts.firstIndex(where: {
                $0.sourceOrdinal == ordinals[activeWindowID]
            }),
            activeIndex != 0
        {
            let active = drafts.remove(at: activeIndex)
            drafts.insert(active, at: 0)
        }
        return drafts
    }

    private func selectedNavigation(
        for tab: ChromiumSessionTab
    ) -> ChromiumSessionNavigation? {
        if let selected = tab.navigations[tab.selectedNavigationIndex] {
            return selected
        }
        let sorted = tab.navigations.values.sorted { $0.index < $1.index }
        return sorted.first(where: { $0.index >= tab.selectedNavigationIndex })
            ?? sorted.last
    }

    private mutating func applyNavigation(_ payload: Data) throws {
        var pickle = try ChromiumPickleReader(payload)
        guard let tabID = pickle.readInt32(),
            let index = pickle.readInt32(),
            let urlString = pickle.readString(maximumByteCount: 8_192),
            let title = pickle.readString16(maximumCodeUnitCount: 4_096),
            pickle.readString(maximumByteCount: 8 * 1_024 * 1_024) != nil,
            pickle.readInt32() != nil
        else {
            throw BrowserTabMigrationError.invalidContents
        }
        guard let url = BrowserTabMigrationSanitizer.url(urlString) else { return }
        let navigation = ChromiumSessionNavigation(
            index: Int(index),
            title: title,
            url: url
        )
        mutateTab(tabID) { $0.navigations[Int(index)] = navigation }
    }

    private mutating func prune(tabID: Int32, index: Int, count: Int) {
        mutateTab(tabID) { tab in
            let upperBound = index.addingReportingOverflow(count)
            guard !upperBound.overflow else { return }
            var rebuilt: [Int: ChromiumSessionNavigation] = [:]
            for navigation in tab.navigations.values {
                if navigation.index < index {
                    rebuilt[navigation.index] = navigation
                } else if navigation.index >= upperBound.partialValue {
                    let shifted = ChromiumSessionNavigation(
                        index: navigation.index - count,
                        title: navigation.title,
                        url: navigation.url
                    )
                    rebuilt[shifted.index] = shifted
                }
            }
            tab.navigations = rebuilt
            if tab.selectedNavigationIndex >= upperBound.partialValue {
                tab.selectedNavigationIndex -= count
            } else if tab.selectedNavigationIndex >= index {
                tab.selectedNavigationIndex = max(0, index - 1)
            }
        }
    }

    private mutating func mutateTab(
        _ id: Int32,
        _ mutation: (inout ChromiumSessionTab) -> Void
    ) {
        guard !closedTabIDs.contains(id) else { return }
        var tab = tabs[id] ?? ChromiumSessionTab(lastActivatedAt: importedAt)
        mutation(&tab)
        tabs[id] = tab
    }

    private mutating func ensureWindow(_ id: Int32) {
        guard !closedWindowIDs.contains(id), windows[id] == nil else { return }
        windows[id] = ChromiumSessionWindow()
    }

    private mutating func mutateWindow(
        _ id: Int32,
        _ mutation: (inout ChromiumSessionWindow) -> Void
    ) {
        guard !closedWindowIDs.contains(id) else { return }
        var window = windows[id] ?? ChromiumSessionWindow()
        mutation(&window)
        windows[id] = window
    }
}
