import SwiftUI

/// The welcome: Crest's mark, a greeting and what setup will do, and, when
/// iCloud brought this device Spaces already set up, that it did, as the
/// preview shows them. Continue walks through the steps.
struct BrowserSetupRootPage: View {
    // MARK: - Variables

    let welcome: BrowserOnboardingWelcomeAction

    // MARK: - Actions - Drawing

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserSetupRootPageMetrics.spacing) {
            CrestStartPageMark()
                .frame(width: BrowserSetupRootPageMetrics.markSize, height: BrowserSetupRootPageMetrics.markSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CrestSpacing.small) {
                Text("Welcome to Crest")
                    .font(BrowserSetupRootPageMetrics.titleFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    welcome.opensCrest
                        ? "Your Spaces came in from iCloud, ready to use."
                        : "Bring your tabs over, then set up your Spaces."
                )
                .font(BrowserSetupRootPageMetrics.bodyFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BrowserSetupRootPageMetrics.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: BrowserSetupRootPageMetrics.alignment)
    }
}

enum BrowserSetupRootPageMetrics {
    #if os(macOS)
        /// The welcome sits in the middle of the panel.
        static let alignment = Alignment.leading
        static let spacing: CGFloat = 20
        static let markSize: CGFloat = 52
        static let titleFont = Font.largeTitle.weight(.bold)
        static let bodyFont = Font.title3
        static let inset = EdgeInsets(top: 0, leading: 30, bottom: 40, trailing: 30)
    #else
        static let alignment = Alignment.topLeading
        static let spacing: CGFloat = 16
        static let markSize: CGFloat = 44
        static let titleFont = Font.largeTitle.weight(.bold)
        static let bodyFont = Font.body
        static let inset = EdgeInsets(top: 16, leading: 20, bottom: 12, trailing: 20)
    #endif
}
