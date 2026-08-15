import Foundation

struct BrowserTabIconSessionState: Equatable, Sendable {
    typealias Item = BrowserTabIconSessionItem

    let items: [Item]

    init(items: [Item]) {
        self.items = items
    }

    init(session: BrowserSession) {
        self.init(items: session.spaces.flatMap { space in
            space.tabs.map { tab in
                Item(
                    id: tab.id,
                    url: tab.url,
                    faviconData: tab.faviconData,
                    faviconURL: tab.faviconURL,
                    iconAccent: tab.iconAccent,
                    iconMode: tab.iconMode,
                    symbol: tab.symbol
                )
            }
        })
    }
}
