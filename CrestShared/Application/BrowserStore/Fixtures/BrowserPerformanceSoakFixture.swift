import Foundation

enum BrowserPerformanceSoakFixture {
    private static let allowedTabCounts = 2...24
    private static let allowedRunIDCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    static func makeSession(
        baseURLString: String?,
        rawTabCount: String?,
        runID: String
    ) -> BrowserSession? {
        guard let baseURLString,
              let baseURL = URL(string: baseURLString),
              isSafeLoopback(baseURL),
              let rawTabCount,
              let tabCount = Int(rawTabCount),
              allowedTabCounts.contains(tabCount),
              isSafeRunID(runID) else { return nil }
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

    private static func isSafeLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http",
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host() ?? "")
    }

    private static func isSafeRunID(_ runID: String) -> Bool {
        guard (1...64).contains(runID.count) else { return false }
        return runID.unicodeScalars.allSatisfy(allowedRunIDCharacters.contains)
    }

    private static func performanceTab(
        index: Int,
        runID: String,
        baseURL: URL
    ) -> BrowserTab? {
        let fixtureURL = baseURL.appending(path: "performance.html")
        guard var components = URLComponents(
            url: fixtureURL,
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "run", value: runID),
            URLQueryItem(name: "tab", value: String(index))
        ]
        if index == 1 {
            components.queryItems?.append(URLQueryItem(name: "mutate", value: "1"))
        }
        if index == 2 {
            components.queryItems?.append(URLQueryItem(name: "video", value: "1"))
        }
        guard let url = components.url else { return nil }
        return BrowserTab(
            title: "Performance \(index)",
            url: url,
            symbol: "gauge.with.dots.needle.67percent",
            placement: .current
        )
    }
}
