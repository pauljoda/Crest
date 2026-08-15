import SwiftUI

struct MobileSpaceCustomizationControls: View {
    let browser: BrowserStore
    let space: BrowserSpace
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Identity")
                    .font(.headline)
                TextField(
                    "Name",
                    text: browser.spaceIdentityBinding(\.name, in: space)
                )
                .accessibilityIdentifier("space-name-field")
            }

            BrowserSpaceBrandingEditor(
                branding: browser.spaceBrandingBinding(in: space),
                symbol: browser.spaceIdentityBinding(\.symbol, in: space),
                compact: compact,
                showsPreview: false
            )
        }
        .frame(width: compact ? nil : 280, alignment: .leading)
        .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mobile-space-customization-controls")
    }
}

#Preview("Mobile Space Customization Controls", traits: .fixedLayout(width: 320, height: 560)) {
    let fixture = MobileBrowserPreviewFixture()
    MobileSpaceCustomizationControls(
        browser: fixture.browser,
        space: fixture.space,
        compact: true
    )
    .padding()
}
