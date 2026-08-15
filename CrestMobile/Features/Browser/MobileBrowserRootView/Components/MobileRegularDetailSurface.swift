import SwiftUI

struct MobileRegularDetailSurface<Content: View>: View {
    let adjoinsLeadingSidebar: Bool
    let isStartPage: Bool
    let hasActivePage: Bool
    let hasSelectedSpace: Bool
    let handleWebContentInteraction: () -> Void
    let content: Content

    var body: some View {
        BrowserRootContentSurface(
            cornerRadius: BrowserChromeLayout.pageCornerRadius,
            seamWidth: BrowserChromeLayout.pageBrandSeamWidth,
            frameInsets: BrowserChromeLayout.pageFrameInsets(
                adjoinsLeadingSidebar: adjoinsLeadingSidebar
            ),
            usesTransparentInnerSurface:
                BrowserPageSurfacePolicy.usesTransparentInnerSurface(
                    isStartPage: isStartPage,
                    hasActivePage: hasActivePage
                ),
            showsFallbackBorder: !hasSelectedSpace
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

#Preview("Mobile Regular Detail Surface") {
    MobileRegularDetailSurface(
        adjoinsLeadingSidebar: true,
        isStartPage: false,
        hasActivePage: true,
        hasSelectedSpace: true,
        handleWebContentInteraction: {},
        content: Color(uiColor: .systemBackground)
    )
}
