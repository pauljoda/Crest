import Foundation

enum CrestSpaceSelectorPreviewFixture {
    static let workSpace = makeSpace(
        idByte: 0x11,
        profileByte: 0x21,
        name: "Work",
        symbol: "briefcase.fill",
        accent: .indigo,
        accessPolicy: .open
    )

    static let privateSpace = makeSpace(
        idByte: 0x12,
        profileByte: 0x22,
        name: "Private",
        symbol: "lock.fill",
        accent: .rose,
        accessPolicy: .deviceOwnerAuthentication
    )

    static let spaces = [workSpace, privateSpace]
    static let identities = CrestSpaceIdentity.list(spaces)

    static func selectedSpaceID(
        for variant: CrestSpaceSelectorPreviewVariant
    ) -> SpaceID? {
        switch variant {
        case .menu, .chips:
            workSpace.id
        case .icons:
            privateSpace.id
        }
    }

    private static func makeSpace(
        idByte: UInt8,
        profileByte: UInt8,
        name: String,
        symbol: String,
        accent: SpaceAccent,
        accessPolicy: BrowserSpaceAccessPolicy
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(rawValue: deterministicUUID(finalByte: idByte)),
            profile: BrowsingProfile(
                id: deterministicUUID(finalByte: profileByte)
            ),
            name: name,
            symbol: symbol,
            accent: accent,
            branding: .initial(accent: accent, symbol: symbol),
            folders: [],
            tabs: [],
            accessPolicy: accessPolicy,
            selectedTabID: nil
        )
    }

    private static func deterministicUUID(finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x45, 0x4C,
                0x45, 0x43,
                0x54, 0x4F, 0x52, 0x53, 0x50, finalByte
            ))
    }
}
