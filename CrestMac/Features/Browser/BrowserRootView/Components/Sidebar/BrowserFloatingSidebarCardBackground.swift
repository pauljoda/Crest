import AppKit
import SwiftUI

struct BrowserFloatingSidebarCardBackground: View {
    let space: BrowserSpace?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if let space {
                BrowserSpaceBannerBackground(branding: space.branding)
                    .opacity(BrowserFloatingSidebarThemePolicy.spaceThemeOpacity)
            }

            if !reduceTransparency {
                LinearGradient(
                    colors: [
                        .white.opacity(
                            BrowserRootMetrics.floatingSidebarHighlightOpacity
                        ),
                        .clear,
                        .black.opacity(
                            BrowserRootMetrics.floatingSidebarShadeOpacity
                        ),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Floating Sidebar Background", traits: .fixedLayout(width: 300, height: 620)) {
    BrowserFloatingSidebarCardBackground(
        space: BrowserRootPreviewFixture.space
    )
}
