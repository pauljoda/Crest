import SwiftUI

struct MobileRegularDetailSurface<Content: View>: View {
    let adjoinsLeadingSidebar: Bool
    let usesBorderlessFrame: Bool
    let isStartPage: Bool
    let hasActivePage: Bool
    let hasSelectedSpace: Bool
    let handleWebContentInteraction: () -> Void
    let content: Content

    var body: some View {
        BrowserRootContentSurface(
            cornerRadius: usesBorderlessFrame
                ? 0
                : BrowserChromeLayout.pageCornerRadius,
            seamWidth: usesBorderlessFrame
                ? 0
                : BrowserChromeLayout.pageBrandSeamWidth,
            frameInsets: usesBorderlessFrame
                ? EdgeInsets()
                : BrowserChromeLayout.pageFrameInsets(
                    adjoinsLeadingSidebar: adjoinsLeadingSidebar
                ),
            usesTransparentInnerSurface:
                BrowserPageSurfacePolicy.usesTransparentInnerSurface(
                    isStartPage: isStartPage,
                    hasActivePage: hasActivePage
                ),
            showsFallbackBorder: !hasSelectedSpace,
            showsBoundary: !usesBorderlessFrame
        ) {
            content
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                handleWebContentInteraction()
            }
        )
    }
}
