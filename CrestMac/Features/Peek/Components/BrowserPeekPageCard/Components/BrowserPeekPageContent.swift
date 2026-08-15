import SwiftUI

struct BrowserPeekPageContent: View {
    let page: BrowserPage?
    let browser: BrowserStore
    let pages: BrowserPagePool?
    let wasReleasedForMemoryPressure: Bool
    let restore: () -> Void

    var body: some View {
        if let page, let pages {
            BrowserWebContentView(
                page: page,
                browser: browser,
                pages: pages
            )
        } else if wasReleasedForMemoryPressure {
            BrowserPeekReleasedPageView(restore: restore)
        } else {
            BrowserPeekLoadingPageView()
        }
    }
}

#Preview {
    BrowserPeekPageContent(
        page: nil,
        browser: BrowserPeekPreviewFixture.makeBrowser(),
        pages: nil,
        wasReleasedForMemoryPressure: false,
        restore: {}
    )
    .frame(width: 640, height: 420)
}
