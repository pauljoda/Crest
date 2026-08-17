import SwiftUI

struct MobileBrowserStartPageHeader: View {
    let isPrivateBrowsing: Bool
    let colorScheme: ColorScheme

    var body: some View {
        Group {
            CrestStartPageMark()
                .frame(
                    width: MobileBrowserChromeLayout.startPageMarkSize,
                    height: MobileBrowserChromeLayout.startPageMarkSize
                )
                .accessibilityHidden(true)
            Text("Start Page")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if isPrivateBrowsing {
                VStack(spacing: MobileBrowserChromeLayout.privateNoticeSpacing) {
                    Label(
                        "Private Browsing",
                        systemImage: BrowserPrivateBrowsingAppearance.symbol
                    )
                    .font(.headline)
                    .foregroundStyle(.primary)
                    Text("Crest does not save this session or use Crest Passwords. Website data stays in memory only.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("private-browsing-notice")
            }
        }
        .environment(\.colorScheme, colorScheme)
    }
}
