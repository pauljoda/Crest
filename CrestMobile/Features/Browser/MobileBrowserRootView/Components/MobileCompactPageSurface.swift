import SwiftUI

struct MobileCompactPageSurface<Backdrop: View, Detail: View>: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let selectedTab: BrowserTab?
    let isURLCopiedFeedbackVisible: Bool
    let pageZoomFeedbackLabel: String?
    let reduceMotion: Bool
    let didPromoteTransientPage: () -> Void
    let tabPromotionNamespace: Namespace.ID
    let completePagePresentation: () -> Void
    let backdrop: Backdrop
    let detail: Detail

    @ViewBuilder
    var body: some View {
        let page = ZStack {
            backdrop
            detail
        }
        .interactiveDismissDisabled(
            !MobileFullTabPresentationPolicy.allowsInteractiveDismissal
        )
        .onAppear(perform: completePagePresentation)
        .overlay {
            MobileTransientBrowsingOverlay(
                browser: browser,
                pages: pages,
                coordinator: transientBrowsing,
                spaceAccess: spaceAccess,
                didPromote: didPromoteTransientPage
            )
        }
        .overlay(alignment: .top) {
            MobileURLCopyFeedback(
                isVisible: isURLCopiedFeedbackVisible,
                topPadding: MobileBrowserRootLayout.compactOverlayTopPadding
            )
            if let pageZoomFeedbackLabel {
                MobilePageZoomFeedback(
                    label: pageZoomFeedbackLabel,
                    topPadding: MobileBrowserRootLayout.compactOverlayTopPadding
                )
            }
        }

        if reduceMotion {
            page
        } else if let selectedTab,
            MobileTabPromotionPolicy.isTransitionSource(
                selectedTab,
                selectedTabID: selectedTab.id
            )
        {
            page.navigationTransition(
                .zoom(
                    sourceID: MobileTabPromotionPolicy.destinationID(
                        for: selectedTab.id
                    ),
                    in: tabPromotionNamespace
                )
            )
        } else {
            page
        }
    }
}

#Preview("Mobile Compact Page Surface") {
    @Previewable @Namespace var tabPromotionNamespace
    let fixture = MobileBrowserPreviewFixture()

    MobileCompactPageSurface(
        browser: fixture.browser,
        pages: fixture.pages,
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        spaceAccess: fixture.spaceAccess,
        selectedTab: nil,
        isURLCopiedFeedbackVisible: false,
        pageZoomFeedbackLabel: nil,
        reduceMotion: false,
        didPromoteTransientPage: {},
        tabPromotionNamespace: tabPromotionNamespace,
        completePagePresentation: {},
        backdrop: Color.indigo.opacity(0.1),
        detail: ContentUnavailableView("Preview Page", systemImage: "globe")
    )
}
