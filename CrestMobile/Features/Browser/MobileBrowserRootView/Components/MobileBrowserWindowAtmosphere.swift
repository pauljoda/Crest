import SwiftUI

struct MobileBrowserWindowAtmosphere: View {
    let space: BrowserSpace?

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if let space {
                BrowserSpaceBannerBackground(branding: space.branding)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Mobile Browser — Window Atmosphere", traits: .fixedLayout(width: 390, height: 220)) {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserWindowAtmosphere(space: fixture.space)
}
