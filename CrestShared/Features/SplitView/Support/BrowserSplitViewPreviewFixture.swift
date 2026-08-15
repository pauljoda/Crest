import Foundation

/// Fixed cards for the shared Split View previews.
///
/// Every identity and date is a literal so a preview renders the same columns
/// on every pass, and nothing here touches a profile, a page pool, or disk.
enum BrowserSplitViewPreviewFixture {
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    static let groupID = SplitGroupID(rawValue: uuid(0x01))
    /// The Space profile the previews resolve favicons against.
    static let profileID = uuid(0x02)
    static let leadingTabID = TabID(rawValue: uuid(0x11))
    static let middleTabID = TabID(rawValue: uuid(0x12))
    static let trailingTabID = TabID(rawValue: uuid(0x13))

    static let members: [BrowserTab] = [
        member(id: leadingTabID, title: "Release Notes", path: "release-notes"),
        member(id: middleTabID, title: "Layout Research", path: "layout-research"),
        member(id: trailingTabID, title: "Split View Spec", path: "split-view-spec"),
    ]

    static var pair: [BrowserTab] {
        Array(members.prefix(2))
    }

    /// The row as it is drawn part-way through a card being carried: the middle
    /// member has reached the leading slot, and the two it passed have closed up
    /// behind it. Still three members with three identities — a carry reorders
    /// the row it is already in rather than adding anything to it.
    static var carriedMiddleToLeadingSlot: [BrowserTab] {
        [members[1], members[0], members[2]]
    }

    private static func member(
        id: TabID,
        title: String,
        path: String
    ) -> BrowserTab {
        BrowserTab(
            id: id,
            title: title,
            url: url(path),
            symbol: "globe",
            placement: .current,
            splitGroupID: groupID,
            lastActivatedAt: fixedDate
        )
    }

    private static func url(_ path: String) -> URL {
        guard let url = URL(string: "crest-preview://split-view/\(path)") else {
            preconditionFailure("The Split View preview URL is invalid.")
        }
        return url
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x50, 0x4C,
                0x49, 0x54,
                0x50, 0x52, 0x45, 0x56, 0x57, finalByte
            ))
    }
}
