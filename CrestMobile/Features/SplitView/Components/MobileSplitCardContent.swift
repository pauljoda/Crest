import SwiftUI

/// One split card's interior on iOS and iPadOS: the per-member twin of what
/// `MobileBrowserDetailView` renders for the selected tab.
///
/// Both platforms' split surfaces use it — the iPhone carousel for the cell it
/// is paging to, the iPad columns for each column — because the difference
/// between them is the viewport they are handed and how focus is asked for, not
/// what a card shows. A live page goes through the same
/// `MobileBrowserLivePageView` the selected tab does, with the same viewport, so
/// a grouped tab renders exactly like the plain tab it is.
///
/// A card resolves its **own** member's page. That is not a stylistic
/// preference: `MobileBrowserWebHostView.attach(_:)` silently takes a web view
/// away from whatever superview already had it, so two cards sharing one page
/// would leave one blank and the other holding a view the first still believes
/// it owns.
///
/// Page-owned chrome — the find bar, the credential prompt — deliberately stays
/// with the focused card in `MobileBrowserDetailView`. A card renders content and
/// nothing else.
struct MobileSplitCardContent: View {
    let member: BrowserTab
    let space: BrowserSpace
    let pages: MobileBrowserPageStore
    let viewport: MobileBrowserPageViewport
    let failureLayout: BrowserNavigationFailureLayout
    /// A tap's request to make this card the focused one. `nil` where focus is
    /// not a tap away, which is every carousel cell: the phone shows one card at
    /// a time, so the card on screen is already the focused one.
    var requestFocus: (() -> Void)?

    var body: some View {
        let page = residentPage
        switch presentation(for: page) {
        case .livePage:
            if let page {
                liveSurface(page)
            } else {
                unloadedSurface
            }
        case .navigationFailure:
            if let page, let failure = page.navigationFailure {
                BrowserNavigationFailureView(
                    failure: failure,
                    branding: space.branding,
                    layout: failureLayout,
                    canGoBack: page.canReturnFromNavigationFailure,
                    canProceed: page.canProceedAfterCertificateFailure,
                    retry: page.retryAfterNavigationFailure,
                    goBack: page.returnFromNavigationFailure,
                    proceed: page.proceedAfterCertificateFailure
                )
                .modifier(MobileSplitCardFocusTapModifier(requestFocus: requestFocus))
            } else {
                unloadedSurface
            }
        case .processFailure:
            if let page {
                BrowserNavigationFailureView(
                    failure: .webContentProcessStopped(url: page.displayURL),
                    branding: space.branding,
                    layout: failureLayout,
                    canGoBack: false,
                    canProceed: false,
                    retry: page.retryAfterProcessFailure,
                    goBack: {},
                    proceed: {}
                )
                .modifier(MobileSplitCardFocusTapModifier(requestFocus: requestFocus))
            } else {
                unloadedSurface
            }
        case .noSelection, .startPage, .unloaded, .automaticRestore:
            // A Start Page has no committed navigation to render beside its
            // siblings, and an evicted neighbour is waiting for the carousel to
            // approach it again. Both read as an empty card rather than as
            // chrome that would claim the space.
            unloadedSurface
        }
    }

    private func liveSurface(_ page: MobileBrowserPage) -> some View {
        MobileBrowserLivePageView(
            page: page,
            viewport: viewport,
            requestFocus: requestFocus
        )
    }

    private var unloadedSurface: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
            .modifier(MobileSplitCardFocusTapModifier(requestFocus: requestFocus))
    }

    /// The card's page, or `nil` when this member has no live runtime right now —
    /// never yet prepared, or reclaimed under critical pressure.
    private var residentPage: MobileBrowserPage? {
        pages.residentPage(
            matching: BrowserTabRuntimeAssignment(
                tabID: member.id,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
    }

    private func presentation(
        for page: MobileBrowserPage?
    ) -> BrowserPagePresentation {
        BrowserPagePresentationPolicy.resolve(
            BrowserPagePresentationInput(
                selection: member.isStartPage ? .startPage : .webPage,
                hasActivePage: page != nil,
                hasNavigationFailure: page?.navigationFailure != nil,
                hasProcessFailure: page?.showsProcessFailure == true,
                // A card never self-restores. Membership decides what is on
                // screen, and the surface that owns the card asks for the page.
                unloadedBehavior: .remainUnloaded
            )
        )
    }
}

#Preview("Split Card — Unloaded Member", traits: .fixedLayout(width: 320, height: 480)) {
    let fixture = MobileBrowserPreviewFixture()

    MobileSplitCardContent(
        member: BrowserSplitViewPreviewFixture.members[0],
        space: fixture.space,
        pages: fixture.pages,
        viewport: .inline,
        failureLayout: .regular
    )
    .background(.quaternary)
}
