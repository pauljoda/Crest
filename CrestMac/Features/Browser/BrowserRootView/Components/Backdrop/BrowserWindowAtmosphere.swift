import AppKit
import SwiftUI

struct BrowserWindowAtmosphere: View {
    let space: BrowserSpace?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let space {
                BrowserSpaceBannerBackground(branding: space.branding)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Window Atmosphere", traits: .fixedLayout(width: 560, height: 320)) {
    BrowserWindowAtmosphere(space: BrowserRootPreviewFixture.space)
}
