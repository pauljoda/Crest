import SwiftUI

struct BrowserWindowAtmosphere: View {
    let space: BrowserSpace?

    var body: some View {
        ZStack {
            platformBackground
            if let space {
                BrowserSpaceBannerBackground(branding: space.branding)
            }
        }
        .accessibilityHidden(true)
    }

    private var platformBackground: Color {
        BrowserPlatformWindowAtmosphereStyle.backgroundColor
    }
}
