import SwiftUI

/// The window's own address bar laid over the top of the page it heads, while
/// the address bar is on top.
///
/// The bar stands in the window rather than in the Space pager, like the
/// sidebar's field, so it stays put while Spaces page underneath, and it shares
/// the sidebar field's identity so the two placements carry one field between
/// them. This layer is the one reader of what a tab switch changes here, the
/// shown page and whether it is a split, so a switch redraws the layer rather
/// than the whole window.
///
/// It steps aside, without leaving, for what draws over the page: a Peek of
/// the shown tab, and a swipe bringing a split into view, whose cards carry
/// bars of their own.
struct BrowserWindowAddressBarLayer: View {
    // MARK: - Variables

    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    /// The page area the bar heads.
    let page: Anchor<CGRect>?
    let commandSurfaceNamespace: Namespace.ID

    @Environment(\.spacePagerPresentation) private var pagerPresentation
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipe = BrowserWindowBarSwipeWatch()

    var body: some View {
        GeometryReader { proxy in
            if let page {
                let frame = BrowserChromeAppearance.placementFrame(
                    for: proxy[page], in: proxy.size.width, direction: layoutDirection)
                bar
                    .frame(width: frame.width)
                    .position(x: frame.midX, y: frame.minY + BrowserPageBarMetrics.topSectionHeight / 2)
            }
        }
        .opacity(stepsAside ? 0 : 1)
        .allowsHitTesting(!stepsAside)
        .accessibilityHidden(stepsAside)
        .animation(CrestMotion.surface.unlessReducingMotion(reduceMotion), value: stepsAside)
        // A page joining or leaving a split hands the top of the page between
        // the window's bar and the cards' own.
        .animation(
            CrestMotion.collection.unlessReducingMotion(reduceMotion),
            value: model.showsPageCardBars && model.presentsSplitBars
        )
        .onChange(of: model.showsPageCardBars, initial: true) { _, onTop in
            if onTop { connectSwipe() } else { swipe.disconnect() }
        }
        .onDisappear { swipe.disconnect() }
    }

    @ViewBuilder
    private var bar: some View {
        let isShown = model.showsWindowTopBar && model.pages.activePage?.isContentFullscreen != true
        let sidebarOnRight = BrowserDeviceAppearanceStore.shared.sidebarOnRight
        ZStack {
            if isShown, let space = model.browser.shownSpace {
                BrowserWindowAddressBar(model: model, space: space, commandSurfaceNamespace: commandSurfaceNamespace)
                    .transition(BrowserWindowChromeMorph.topBarTransition(fromLeading: !sidebarOnRight))
            }
        }
        .animation(CrestMotion.chrome.unlessReducingMotion(reduceMotion), value: isShown)
    }

    /// Whether something drawn over the page has the top of it now.
    private var stepsAside: Bool {
        guard model.showsPageCardBars else { return false }
        return swipe.showsSplitInView || showsPeek
    }

    /// Whether a Peek of the shown tab stands over the page.
    private var showsPeek: Bool {
        let requests = transientBrowsing.peekRequests
        guard !requests.isEmpty, let shownTabID = model.browser.shownTab?.id else { return false }
        return requests.contains { $0.sourceTabID == shownTabID }
    }

    // MARK: - Actions - Swipe

    private func connectSwipe() {
        let browser = model.browser
        swipe.connect(pagerPresentation) { spaceID in
            guard let space = browser.availableSpaces.first(where: { $0.id == spaceID }) else { return false }
            return browser.cards(in: space).count > 1
        }
    }
}
