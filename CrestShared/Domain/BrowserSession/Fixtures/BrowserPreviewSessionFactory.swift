import Foundation

enum BrowserPreviewSessionFactory {
    static func make() -> BrowserSession {
        let work = makeWorkSpace()
        let personal = makePersonalSpace()
        return BrowserSession(spaces: [work, personal], selectedSpaceID: work.id)
    }

    private static func makeWorkSpace() -> BrowserSpace {
        let folder = BrowserFolder(title: "Build the Browser", symbol: "folder.fill")
        let tabs = workTabs(folderID: folder.id)
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            branding: .initial(accent: .indigo, symbol: "briefcase.fill"),
            folders: [folder],
            tabs: tabs,
            selectedTabID: tabs.last?.id
        )
    }

    private static func workTabs(folderID: FolderID) -> [BrowserTab] {
        [
            tab("Apple", "https://apple.com", "apple.logo", .pinned),
            tab("GitHub", "https://github.com", "chevron.left.forwardslash.chevron.right", .pinned),
            tab("Linear", "https://linear.app", "line.3.horizontal.decrease.circle.fill", .pinned),
            tab("WebKit", "https://webkit.org", "safari.fill", .pinned),
            tab(
                "Apple sidebars",
                "https://developer.apple.com/design/human-interface-guidelines/sidebars",
                "sidebar.left",
                .saved,
                folderID
            ),
            tab(
                "WebKit for SwiftUI",
                "https://developer.apple.com/videos/play/wwdc2025/231/",
                "play.rectangle.fill",
                .saved,
                folderID
            ),
            tab(
                "SwiftUI",
                "https://developer.apple.com/xcode/swiftui/",
                "swift",
                .saved,
                folderID
            ),
            tab(
                "Liquid Glass notes",
                "https://developer.apple.com/documentation/technologyoverviews/liquid-glass",
                "drop.fill",
                .current
            ),
            BrowserTab.startPage(),
        ]
    }

    private static func makePersonalSpace() -> BrowserSpace {
        let folder = BrowserFolder(title: "Reading", symbol: "folder.fill")
        let tabs = [
            tab("Apple", "https://apple.com", "apple.logo", .pinned),
            tab("YouTube", "https://youtube.com", "play.fill", .pinned),
            tab("Music", "https://music.apple.com", "music.note", .pinned),
            tab("Maps", "https://maps.apple.com", "map.fill", .pinned),
            tab("WebKit blog", "https://webkit.org/blog/", "text.page.fill", .saved, folder.id),
            tab("Weekend ideas", "https://www.nps.gov", "leaf.fill", .current),
        ]
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Personal",
            symbol: "house.fill",
            accent: .orange,
            branding: .initial(accent: .orange, symbol: "house.fill"),
            folders: [folder],
            tabs: tabs,
            selectedTabID: tabs.last?.id
        )
    }

    private static func tab(
        _ title: String,
        _ urlString: String,
        _ symbol: String,
        _ placement: TabPlacement,
        _ folderID: FolderID? = nil
    ) -> BrowserTab {
        BrowserTab(
            title: title,
            url: URL(string: urlString),
            symbol: symbol,
            placement: placement,
            folderID: folderID,
            lastActivatedAt: .now
        )
    }
}

// MARK: - Cleanup Fixture

extension BrowserSession {
    static func cleanupFixture(now: Date) -> BrowserSession {
        var session = preview
        guard let spaceIndex = session.spaces.firstIndex(where: { $0.id == session.selectedSpaceID }) else {
            return session
        }
        let selectedID = session.spaces[spaceIndex].selectedTabID
        for tabIndex in session.spaces[spaceIndex].tabs.indices {
            let tab = session.spaces[spaceIndex].tabs[tabIndex]
            if tab.placement == .current, tab.id != selectedID {
                session.spaces[spaceIndex].tabs[tabIndex].lastActivatedAt = now.addingTimeInterval(-13 * 60 * 60)
            }
        }
        let expired = BrowserTab(
            title: "Old research",
            url: URL(string: "https://example.com/old"),
            placement: .current,
            lastActivatedAt: now.addingTimeInterval(-13 * 60 * 60)
        )
        session.spaces[spaceIndex].tabs.append(expired)
        return session
    }
}

// MARK: - Browser Session

extension BrowserSession {
    static let preview: BrowserSession = BrowserPreviewSessionFactory.make()
}
