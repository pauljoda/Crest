import SwiftUI

struct MobileBrowserStartPageBackground: View {
    let space: BrowserSpace?
    let usesCommandPalette: Bool

    var body: some View {
        Group {
            if !usesCommandPalette, let space {
                BrowserSpaceBannerBackground(branding: space.branding)
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview("Mobile Browser Start Page Background") {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserStartPageBackground(
        space: fixture.space,
        usesCommandPalette: false
    )
}
