import Foundation

enum BrowserPerformanceSoakFixture {
    private static let allowedTabCounts = 2...24
    private static let allowedRunIDCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    static func makeSession(
        baseURLString: String?,
        rawTabCount: String?,
        isHeavy: Bool = false,
        runID: String
    ) -> BrowserSession? {
        guard let baseURLString,
            let baseURL = URL(string: baseURLString),
            isSafeLoopback(baseURL),
            let rawTabCount,
            let tabCount = Int(rawTabCount),
            allowedTabCounts.contains(tabCount),
            isSafeRunID(runID)
        else { return nil }
        if isHeavy {
            return makeHeavySession(
                baseURL: baseURL,
                tabCount: tabCount,
                runID: runID
            )
        }
        let profile = BrowsingProfile()
        let tabs = (1...tabCount).compactMap { tabIndex in
            performanceTab(
                index: tabIndex,
                runID: runID,
                baseURL: baseURL
            )
        }
        guard tabs.count == tabCount, let firstTab = tabs.first else { return nil }
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Performance",
            symbol: "gauge.with.dots.needle.67percent",
            accent: .teal,
            folders: [],
            tabs: tabs,
            browsingPreferences: BrowserSpaceBrowsingPreferences(
                searchProvider: .google,
                currentTabCleanupPolicy: .never,
                contentBlockingPolicy: .off
            ),
            selectedTabID: firstTab.id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }

    private static func makeHeavySession(
        baseURL: URL,
        tabCount: Int,
        runID: String
    ) -> BrowserSession? {
        let spaces = (1...6).compactMap { spaceIndex -> BrowserSpace? in
            let folders = (1...8).map { folderIndex in
                BrowserFolder(title: "Collection \(spaceIndex)-\(folderIndex)")
            }
            let tabs = (1...tabCount).compactMap { tabIndex -> BrowserTab? in
                let placement: TabPlacement =
                    tabIndex.isMultiple(of: 3)
                    ? .saved
                    : .current
                let folderID =
                    placement == .saved
                    ? folders[(tabIndex / 3 - 1) % folders.count].id
                    : nil
                return performanceTab(
                    index: (spaceIndex - 1) * tabCount + tabIndex,
                    runID: runID,
                    baseURL: baseURL,
                    placement: placement,
                    folderID: folderID
                )
            }
            guard tabs.count == tabCount,
                let firstCurrentTab = tabs.first(where: { $0.placement == .current })
            else { return nil }
            let history = (1...96).compactMap { historyIndex -> BrowserHistoryEntry? in
                guard
                    let url = performanceURL(
                        index: spaceIndex * 1_000 + historyIndex,
                        runID: runID,
                        baseURL: baseURL
                    )
                else { return nil }
                let firstVisit = Date(
                    timeIntervalSince1970: 1_700_000_000
                        + Double(spaceIndex * 1_000 + historyIndex)
                )
                return BrowserHistoryEntry(
                    url: url,
                    title: "History \(spaceIndex)-\(historyIndex)",
                    firstVisitedAt: firstVisit,
                    lastVisitedAt: firstVisit.addingTimeInterval(300),
                    visitCount: historyIndex % 5 + 1
                )
            }
            return BrowserSpace(
                id: SpaceID(),
                profile: BrowsingProfile(),
                name: "Performance \(spaceIndex)",
                symbol: "gauge.with.dots.needle.67percent",
                accent: .teal,
                folders: folders,
                tabs: tabs,
                history: history,
                browsingPreferences: BrowserSpaceBrowsingPreferences(
                    searchProvider: .google,
                    currentTabCleanupPolicy: .never,
                    contentBlockingPolicy: .off
                ),
                selectedTabID: firstCurrentTab.id
            )
        }
        guard spaces.count == 6, let firstSpace = spaces.first else { return nil }
        return BrowserSession(spaces: spaces, selectedSpaceID: firstSpace.id)
    }

    private static func isSafeLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http",
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil
        else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host() ?? "")
    }

    private static func isSafeRunID(_ runID: String) -> Bool {
        guard (1...64).contains(runID.count) else { return false }
        return runID.unicodeScalars.allSatisfy(allowedRunIDCharacters.contains)
    }

    private static func performanceTab(
        index: Int,
        runID: String,
        baseURL: URL,
        placement: TabPlacement = .current,
        folderID: FolderID? = nil
    ) -> BrowserTab? {
        guard
            let url = performanceURL(
                index: index,
                runID: runID,
                baseURL: baseURL
            )
        else { return nil }
        return BrowserTab(
            title: "Performance \(index)",
            url: url,
            symbol: "gauge.with.dots.needle.67percent",
            placement: placement,
            folderID: folderID
        )
    }

    private static func performanceURL(
        index: Int,
        runID: String,
        baseURL: URL
    ) -> URL? {
        let fixtureURL = baseURL.appending(path: "performance.html")
        guard
            var components = URLComponents(
                url: fixtureURL,
                resolvingAgainstBaseURL: false
            )
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "run", value: runID),
            URLQueryItem(name: "tab", value: String(index)),
        ]
        if index == 1 {
            components.queryItems?.append(URLQueryItem(name: "mutate", value: "1"))
        }
        if index == 2 {
            components.queryItems?.append(URLQueryItem(name: "video", value: "1"))
        }
        return components.url
    }
}
