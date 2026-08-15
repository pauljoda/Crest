import SwiftUI

struct BrowserSiteControlHeader: View {
    let page: BrowserPage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(page.title.isEmpty ? "Site Controls" : page.title)
                .font(.headline)
                .lineLimit(1)
            if let host = page.displayURL?.host() {
                Text(host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview("Site Control Header") {
    let preview = BrowserSidebarExtensionPreviewFixture.makeContext()
    BrowserSiteControlHeader(page: preview.configuration.page)
        .padding()
        .frame(width: BrowserSiteControlLayoutPolicy.width)
}
