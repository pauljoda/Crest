import Foundation

@MainActor
enum BrowserManualSetupPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(finalByte: 0x11))
    static let profileID = uuid(finalByte: 0x21)
    static let pinnedTab = BrowserTab(
        id: TabID(rawValue: uuid(finalByte: 0x31)),
        title: "Crest",
        url: url("https://crestbrowser.com"),
        symbol: "pin.fill",
        placement: .pinned,
        lastActivatedAt: date(offset: 400)
    )
    static let savedTab = BrowserTab(
        id: TabID(rawValue: uuid(finalByte: 0x32)),
        title: "Swift",
        url: url("https://swift.org"),
        placement: .saved,
        lastActivatedAt: date(offset: 300)
    )
    static let openTab = BrowserTab(
        id: TabID(rawValue: uuid(finalByte: 0x33)),
        title: "Apple Developer",
        url: url("https://developer.apple.com"),
        placement: .current,
        lastActivatedAt: date(offset: 200)
    )
    static let manualTab = BrowserTab(
        id: TabID(rawValue: uuid(finalByte: 0x34)),
        title: "Example",
        url: url("https://example.com"),
        placement: .saved,
        lastActivatedAt: date(offset: 100)
    )
    static let space = BrowserSpace(
        id: spaceID,
        profile: BrowsingProfile(id: profileID),
        name: "Work",
        symbol: "briefcase.fill",
        accent: .indigo,
        branding: .initial(accent: .indigo, symbol: "briefcase.fill"),
        folders: [],
        tabs: [pinnedTab, savedTab, openTab],
        selectedTabID: openTab.id
    )
    static let existingSession = BrowserSession(
        spaces: [space],
        selectedSpaceID: spaceID
    )
    static let plan = BrowserManualSetupPlan(existing: existingSession)
    static let selectedSpaceID: SpaceID? = spaceID
    static let previewSession = try? plan.preview(mergingInto: existingSession)
    static let draft =
        plan.spaces.first(where: { $0.id == spaceID })
        ?? BrowserManualSetupSpaceDraft(space: space, isNew: false)
    static let suggestion = BrowserSetupSiteSuggestion(
        title: "Wikipedia",
        url: url("https://wikipedia.org"),
        systemImage: "books.vertical.fill",
        defaultPlacement: .saved
    )

    static func model(
        address: String = "example.com",
        errorMessage: String? = nil
    ) -> BrowserManualSetupModel {
        BrowserManualSetupModel(
            address: address,
            placement: .saved,
            errorMessage: errorMessage
        )
    }

    private static func url(_ value: String) -> URL {
        URL(string: value) ?? URL(fileURLWithPath: "/")
    }

    private static func date(offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: offset)
    }

    private static func uuid(finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x4D,
                0x41, 0x4E,
                0x55, 0x41,
                0x4C, 0x53, 0x45, 0x54, 0x55, finalByte
            ))
    }
}
