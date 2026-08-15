import SwiftUI

struct MobileSpaceCustomizationSection: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let browser: BrowserStore
    let space: BrowserSpace

    var body: some View {
        Section("Customize") {
            if Self.usesStableCompactLayout(for: horizontalSizeClass) {
                compactLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    wideLayout
                    compactLayout
                }
            }
        }
    }

    static func usesStableCompactLayout(
        for horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        horizontalSizeClass != .regular
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            MobileSpaceCustomizationPreview(
                space: browser.liveSpace(space),
                wide: true
            )
            MobileSpaceCustomizationControls(
                browser: browser,
                space: space,
                compact: false
            )
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            MobileSpaceCustomizationPreview(
                space: browser.liveSpace(space),
                wide: false
            )
            MobileSpaceCustomizationControls(
                browser: browser,
                space: space,
                compact: true
            )
        }
    }
}

#Preview("Mobile Space Customization") {
    let fixture = MobileBrowserPreviewFixture()
    Form {
        MobileSpaceCustomizationSection(
            browser: fixture.browser,
            space: fixture.space
        )
    }
}
