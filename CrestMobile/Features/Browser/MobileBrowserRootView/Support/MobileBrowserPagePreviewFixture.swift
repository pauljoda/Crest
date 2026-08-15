import Foundation

@MainActor
enum MobileBrowserPagePreviewFixture {
    static func makePage() -> MobileBrowserPage {
        let fixture = MobileBrowserPreviewFixture()
        let tab = BrowserTab(
            id: TabID(
                rawValue: UUID(
                    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
                )
            ),
            title: "Apple Developer",
            url: URL(string: "https://developer.apple.com"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        )
        return MobileBrowserPage(
            tab: tab,
            space: fixture.space,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
    }
}
