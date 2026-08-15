import SwiftUI

struct MobileBrowserRootSurface<Compact: View, Regular: View, Palette: View>:
    View, BrowserChromeAnimating
{
    let presentation: MobileBrowserPresentation
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let preferredSidebarWidth: CGFloat
    let isCommandPalettePresented: Bool
    let isURLCopiedFeedbackVisible: Bool
    let pageZoomFeedbackLabel: String?
    let reduceMotion: Bool
    let didPromoteTransientPage: () -> Void
    let compact: Compact
    let regular: (MobileRegularWindowLayout) -> Regular
    let palette: Palette

    var body: some View {
        ZStack {
            if presentation == .regular,
                MobileRegularBrowserBackdropPolicy.rootOwnsAtmosphere
            {
                MobileBrowserWindowAtmosphere(space: browser.selectedSpace)
                    .ignoresSafeArea(
                        .container,
                        edges: MobileRegularBrowserBackdropPolicy.atmosphereSafeAreaEdges
                    )
            }

            if presentation == .compact {
                compact
            } else {
                GeometryReader { proxy in
                    regular(
                        MobileRegularWindowLayoutPolicy.resolve(
                            availableWidth: proxy.size.width,
                            preferredSidebarWidth: preferredSidebarWidth
                        )
                    )
                    .allowsHitTesting(!isCommandPalettePresented)
                    .accessibilityHidden(isCommandPalettePresented)
                }
            }
        }
        .overlay {
            if presentation == .regular {
                palette
            }
        }
        .overlay {
            if presentation == .regular || !navigation.compactShowsPage {
                MobileTransientBrowsingOverlay(
                    browser: browser,
                    pages: pages,
                    coordinator: transientBrowsing,
                    spaceAccess: spaceAccess,
                    didPromote: didPromoteTransientPage
                )
            }
        }
        .overlay(alignment: .top) {
            if presentation == .regular || !navigation.compactShowsPage {
                MobileURLCopyFeedback(
                    isVisible: isURLCopiedFeedbackVisible,
                    topPadding: presentation == .compact
                        ? MobileBrowserRootLayout.compactOverlayTopPadding
                        : MobileBrowserRootLayout.regularOverlayTopPadding
                )
                if let pageZoomFeedbackLabel {
                    MobilePageZoomFeedback(
                        label: pageZoomFeedbackLabel,
                        topPadding: presentation == .compact
                            ? MobileBrowserRootLayout.compactOverlayTopPadding
                            : MobileBrowserRootLayout.regularOverlayTopPadding
                    )
                }
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .animation(
            chromeAnimation(CrestMotion.pane),
            value: isCommandPalettePresented
        )
    }
}

#Preview("Mobile Browser Root Surface") {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserRootSurface(
        presentation: .compact,
        browser: fixture.browser,
        pages: fixture.pages,
        navigation: MobileBrowserNavigationState(),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        spaceAccess: fixture.spaceAccess,
        preferredSidebarWidth: 320,
        isCommandPalettePresented: false,
        isURLCopiedFeedbackVisible: false,
        pageZoomFeedbackLabel: nil,
        reduceMotion: false,
        didPromoteTransientPage: {},
        compact: ContentUnavailableView("Compact Browser", systemImage: "iphone"),
        regular: { _ in
            ContentUnavailableView("Regular Browser", systemImage: "ipad")
        },
        palette: Color.clear
    )
}
