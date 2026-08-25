import Foundation

@MainActor
enum BrowserCommandPalettePreviewFixture {
    static let selectedTabID = TabID(rawValue: uuid(finalByte: 0x11))

    static let currentSpace = BrowserSpace(
        id: SpaceID(rawValue: uuid(finalByte: 0x21)),
        profile: BrowsingProfile(id: uuid(finalByte: 0x31)),
        name: "Work",
        symbol: "briefcase.fill",
        accent: .indigo,
        folders: [],
        tabs: [
            BrowserTab(
                id: selectedTabID,
                title: "Crest",
                url: url("https://crestbrowser.com"),
                faviconData: faviconData,
                placement: .current,
                lastActivatedAt: date(offset: 400)
            ),
            BrowserTab(
                id: TabID(rawValue: uuid(finalByte: 0x12)),
                title: "Swift Evolution",
                url: url("https://www.swift.org/swift-evolution"),
                faviconData: faviconData,
                placement: .current,
                lastActivatedAt: date(offset: 300)
            ),
            BrowserTab(
                id: TabID(rawValue: uuid(finalByte: 0x13)),
                title: "GitHub",
                url: url("https://github.com"),
                faviconData: faviconData,
                placement: .pinned,
                lastActivatedAt: date(offset: 200)
            ),
        ],
        history: [
            BrowserHistoryEntry(
                id: uuid(finalByte: 0x41),
                url: url("https://forums.swift.org"),
                title: "Swift Forums",
                firstVisitedAt: date(offset: 100),
                lastVisitedAt: date(offset: 500),
                visitCount: 7
            )
        ],
        selectedTabID: selectedTabID
    )

    static let registry = BrowserCommandPaletteCommandRegistry(
        commands: [.newWindow, .showHistory, .showDownloads, .toggleSidebar],
        shortcut: { command in
            guard command == .showHistory else { return nil }
            return BrowserShortcut(
                key: .character("y"),
                modifiers: [.command, .shift]
            )
        },
        perform: { _ in }
    )

    static let intentResult = BrowserCommandPaletteResult(
        section: nil,
        id: "preview-intent",
        title: "Search with Google",
        subtitle: "swift",
        symbol: "magnifyingglass",
        searchProvider: .google,
        trailing: "",
        target: .url(url("https://www.google.com/search?q=swift"))
    )

    static let tabResult = BrowserCommandPaletteResult(
        section: .tabs,
        id: "preview-tab",
        title: "Swift Evolution",
        subtitle: "www.swift.org",
        symbol: "globe",
        trailing: "Switch to Tab",
        target: .tab(
            BrowserTabRuntimeAssignment(
                tabID: TabID(rawValue: uuid(finalByte: 0x12)),
                spaceID: currentSpace.id,
                profileID: currentSpace.profile.id
            )
        )
    )

    static let commandResult = BrowserCommandPaletteResults.actionResult(.showHistory)

    static let historyResult = BrowserCommandPaletteResult(
        section: .history,
        id: "preview-history",
        title: "Swift Forums",
        subtitle: "forums.swift.org",
        symbol: "clock",
        trailing: "Open",
        target: .url(url("https://forums.swift.org"))
    )

    static let intentItem = BrowserCommandPaletteIndexedResult(
        index: 0,
        result: intentResult
    )
    static let tabItem = BrowserCommandPaletteIndexedResult(
        index: 1,
        result: tabResult
    )
    static let commandItem = BrowserCommandPaletteIndexedResult(
        index: 2,
        result: commandResult
    )
    static let tabGroup = BrowserCommandPaletteResultGroup(
        id: "preview-tabs",
        header: BrowserCommandPaletteSection.openTabsTitle,
        items: [tabItem]
    )
    static let mixedItems = [intentItem, tabItem, commandItem]

    static func model(query: String) -> BrowserCommandPaletteModel {
        BrowserCommandPaletteModel(
            space: currentSpace,
            selectedTabID: selectedTabID,
            initialQuery: query,
            commands: registry,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in true },
            openURL: { _, _ in true },
            dismiss: {}
        )
    }

    private static func url(_ value: String) -> URL {
        URL(
            string: value.replacingOccurrences(
                of: "https://",
                with: "crest-preview://"
            )
        ) ?? URL(fileURLWithPath: "/command-palette-preview")
    }

    private static let faviconData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0x60, 0x68, 0xF8, 0xCF,
        0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89,
        0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ])

    private static func date(offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: offset)
    }

    private static func uuid(finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x50,
                0x41, 0x4C,
                0x45, 0x54,
                0x54, 0x45, 0x50, 0x52, 0x45, finalByte
            ))
    }
}
