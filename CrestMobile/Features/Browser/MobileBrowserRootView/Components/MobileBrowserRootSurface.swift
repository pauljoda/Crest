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
    let palette: (EdgeInsets) -> Palette
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ZStack {
            if presentation == .regular {
                SpaceBackdropBlend(
                    spaces: BrowserSidebarAccessPolicy.availableSpaces(in: browser),
                    selectedSpace: browser.selectedSpace
                ) {
                    BrowserWindowAtmosphere(space: $0)
                }
                .ignoresSafeArea()
            }

            if presentation == .compact {
                compact
            } else {
                GeometryReader { proxy in
                    let layout = MobileRegularWindowLayoutPolicy.resolve(
                        availableWidth: proxy.size.width,
                        preferredSidebarWidth: preferredSidebarWidth
                    )
                    regular(layout)
                        .allowsHitTesting(!isCommandPalettePresented)
                        .accessibilityHidden(isCommandPalettePresented)
                        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
                            GeometryReader { pageProxy in
                                let rect = anchor.map { pageProxy[$0] } ?? CGRect(origin: .zero, size: pageProxy.size)
                                palette(
                                    BrowserChromeAppearance.contentInsets(
                                        for: rect, in: pageProxy.size, direction: layoutDirection))
                            }
                        }
                }
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
