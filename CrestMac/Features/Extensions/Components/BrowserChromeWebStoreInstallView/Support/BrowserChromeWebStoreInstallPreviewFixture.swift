import Foundation

@MainActor
enum BrowserChromeWebStoreInstallPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x61))
    static let spaceName = "Research"

    static let candidate: BrowserChromeWebStoreCandidate = {
        guard
            let url = URL(
                string:
                    "https://chromewebstore.google.com/detail/reading-focus/abcdefghijklmnopabcdefghijklmnop"
            ),
            let item = BrowserChromeWebStoreItem(url: url)
        else {
            preconditionFailure("The fixed Chrome Web Store preview URL is invalid.")
        }
        let source = BrowserChromeWebStoreSource(
            extensionID: item.id,
            storeURL: item.storeURL,
            crxSHA256Hex: String(repeating: "a", count: 64),
            publisherKeyHashHex: String(repeating: "b", count: 64)
        )
        return BrowserChromeWebStoreCandidate(
            item: item,
            source: source,
            verifiedPackage: BrowserVerifiedCRX3Package(
                extensionID: item.id,
                crxData: Data(),
                zipArchiveData: Data(),
                crxSHA256Hex: source.crxSHA256Hex,
                publisherKeyHashHex: source.publisherKeyHashHex
            ),
            displayName: "Reading Focus",
            version: "1.0.0",
            displayDescription:
                "A verified extension for keeping long-form reading distraction free.",
            requestedPermissions: ["storage"],
            requestedHosts: ["https://developer.apple.com/*"],
            errors: [],
            iconPayload: nil,
            hasOptionsPage: true,
            hasCommands: true,
            hasContentModificationRules: true,
            nativeMessagingCapability: .available,
            iCloudPasswordsCapability: .available
        )
    }()

    static func makePage() -> BrowserPage {
        let profileID = uuid(0x62)
        let tabID = TabID(rawValue: uuid(0x63))
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: profileID),
            name: spaceName,
            symbol: "puzzlepiece.extension.fill",
            accent: .indigo,
            branding: .initial(
                accent: .indigo,
                symbol: "puzzlepiece.extension.fill"
            ),
            folders: [],
            tabs: [
                BrowserTab.startPage(
                    id: tabID,
                    lastActivatedAt: fixedDate
                )
            ],
            selectedTabID: tabID
        )
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        guard let tab = space.tabs.first(where: { $0.id == tabID }) else {
            preconditionFailure("The fixed extension preview tab is missing.")
        }
        pages.select(tab: tab, space: space, at: fixedDate)
        guard
            let page = pages.activePage,
            page.spaceID == spaceID,
            page.profileID == profileID
        else {
            preconditionFailure(
                "The extension preview page must retain its fixed Space assignment."
            )
        }
        return page
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x45,
                0x58, 0x54,
                0x45, 0x4E,
                0x53, 0x49, 0x4F, 0x4E, 0x50, finalByte
            ))
    }
}
