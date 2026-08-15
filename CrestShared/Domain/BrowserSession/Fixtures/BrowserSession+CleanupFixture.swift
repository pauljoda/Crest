import Foundation

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
