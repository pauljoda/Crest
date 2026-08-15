import SwiftUI

struct BrowserSiteDeveloperModeStatus: View {
    let page: BrowserPage

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("Developer Mode")
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "hammer.fill")
                .foregroundStyle(
                    page.isDeveloperModeEnabled ? .yellow : .secondary
                )
        }
    }

    private var detail: String {
        if BrowserDeveloperModePolicy.isAutomatic(for: page.displayURL) {
            return "On automatically for localhost"
        }
        return page.isDeveloperModeEnabled ? "On" : "Off"
    }
}

#Preview("Developer Mode Status") {
    let preview = BrowserSiteSettingsPreviewFixture.makePage()
    BrowserSiteDeveloperModeStatus(page: preview.page)
        .padding()
}
