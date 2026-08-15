import SwiftUI

struct BrowserLivePageContent: View {
    let page: BrowserPage?
    let browser: BrowserStore
    let pages: BrowserPagePool

    var body: some View {
        if let page {
            BrowserWebContentView(
                page: page,
                browser: browser,
                pages: pages
            )
        } else {
            BrowserUnloadedPageSurface()
        }
    }
}

#Preview("Browser Live Page Content") {
    let preview = BrowserDetailPreviewFixture.makeWebContent()

    BrowserLivePageContent(
        page: preview.page,
        browser: preview.browser,
        pages: preview.pages
    )
    .frame(width: 960, height: 640)
}
