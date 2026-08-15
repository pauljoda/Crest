import Foundation

@MainActor
enum BrowserShortcutSettingsPreviewFactory {
    static func model(
        searchText: String = ""
    ) -> BrowserShortcutSettingsModel {
        let browser = makeBrowser()
        let model = BrowserShortcutSettingsModel(
            shortcuts: .inMemory(),
            browser: browser,
            extensionCommands: BrowserShortcutPreviewExtensionCommands(),
            searchProvider: BrowserShortcutPresentationCatalog(),
            selectedExtensionSpaceID: browser.session.selectedSpaceID
        )
        model.searchText = searchText
        return model
    }

    private static func makeBrowser() -> BrowserStore {
        let tabID = TabID(rawValue: uuid(0x03))
        let spaceID = SpaceID(rawValue: uuid(0x01))
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: uuid(0x02)),
            name: "Preview Space",
            symbol: "keyboard",
            accent: .indigo,
            folders: [],
            tabs: [
                BrowserTab.startPage(
                    id: tabID,
                    lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ],
            selectedTabID: tabID
        )
        return BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: spaceID
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x48, 0x4F,
                0x52, 0x54,
                0x43, 0x55, 0x54,
                0x50, 0x52, finalByte
            ))
    }
}
