import SwiftUI

struct BrowserFloatingSidebarCardBackground: View {
    let space: BrowserSpace?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            platformBackground

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

    private var platformBackground: Color {
        BrowserPlatformFloatingSidebarCardStyle.backgroundColor
    }
}
