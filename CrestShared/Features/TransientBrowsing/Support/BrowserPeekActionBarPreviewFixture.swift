import Foundation

enum BrowserPeekActionBarPreviewFixture {
    static let workID = SpaceID(rawValue: uuid(0x11))
    static let personalID = SpaceID(rawValue: uuid(0x12))

    static let spaces = [
        BrowserSpace(
            id: workID,
            profile: BrowsingProfile(id: uuid(0x21)),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            branding: .initial(accent: .indigo, symbol: "briefcase.fill"),
            folders: [],
            tabs: [],
            selectedTabID: nil
        ),
        BrowserSpace(
            id: personalID,
            profile: BrowsingProfile(id: uuid(0x22)),
            name: "Personal",
            symbol: "leaf.fill",
            accent: .teal,
            branding: .initial(accent: .teal, symbol: "leaf.fill"),
            folders: [],
            tabs: [],
            selectedTabID: nil
        ),
    ]

    static var selectedSpace: BrowserSpace {
        spaces[0]
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53, 0x54, 0x50, 0x45, 0x45,
                0x4B, 0x50, 0x52, 0x45, 0x56, 0x49, 0x45, finalByte
            )
        )
    }
}
