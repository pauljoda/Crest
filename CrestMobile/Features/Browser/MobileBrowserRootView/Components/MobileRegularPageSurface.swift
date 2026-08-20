import SwiftUI

/// The iPad content area, and the one place that decides between real columns and
/// the single rounded page surface.
///
/// The branch sits here rather than inside `MobileRegularDetailSurface` because
/// the columns view *replaces* that surface instead of living inside it: it
/// applies the outer page insets itself and wraps each card in its own
/// `BrowserRootContentSurface`, so nesting the two would draw a bordered, shadowed
/// surface inside another one. macOS makes the same call at the same level in
/// `BrowserRootPageSurface`.
///
/// A locked Space is excluded, matching macOS: the page store has already dropped
/// every card, and half a split left on screen behind a lock gate is the privacy
/// failure the gate exists to prevent.
///
/// It is also where a tab dragged out of the sidebar becomes a card, through the
/// very modifiers macOS registers — the content area as a zone, the presented
/// cards as frames — plus the one thing a touch shell has to add: a feed that
/// carries the finger's positions to the reorder state while it is over the page.
struct MobileRegularPageSurface: View {
    let model: MobileBrowserRootModel
    let adjoinsLeadingSidebar: Bool
    let usesCollapsedSidebarBorderlessFrame: Bool
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let isCommandPalettePresented: Bool
    let compactToolbarIsHidden: Bool
    let submitAddress: () -> Void
    let beginNewTab: () -> Void
    let showTabViewer: () -> Void
    let hideCompactToolbar: () -> Void
    let showCompactToolbar: () -> Void
    let handleToolbarSwipe: (BrowserSpaceSwipeDirection) -> Void
    let selectSplitCard: (TabID) -> Void
    let compactTransitionEnded: (CGSize) -> Void

    var body: some View {
        surface
            .browserSplitContentDropZone(
                assignment: presentedAssignment,
                state: model.browser.sidebarReorderState
            )
            .modifier(
                MobileSplitContentDropFeed(
                    browser: model.browser,
                    spaceAccess: model.spaceAccess
                )
            )
    }

    @ViewBuilder
    private var surface: some View {
        if let splitPresentation {
            MobileSplitColumnsPageSurface(
                model: model,
                space: splitPresentation.space,
                members: splitPresentation.members,
                adjoinsLeadingSidebar: adjoinsLeadingSidebar,
                placeholderIndex: splitInsertIndex
            )
        } else {
            MobileRegularDetailSurface(
                adjoinsLeadingSidebar: adjoinsLeadingSidebar,
                usesBorderlessFrame: usesCollapsedSidebarBorderlessFrame,
                isStartPage: model.browser.selectedTab?.isStartPage == true,
                hasActivePage: model.selectedPage != nil,
                hasSelectedSpace: model.browser.selectedSpace != nil,
                handleWebContentInteraction: {
                    model.navigation.utilityPresentation
                        .handleInteraction(.webContent)
                    model.navigation.handleRegularPageInteraction()
                },
                content: MobileBrowserDetailSurface(
                    browser: model.browser,
                    pages: model.pages,
                    spaceAccess: model.spaceAccess,
                    address: $address,
                    isAddressEditing: $isAddressEditing,
                    addressFocusRequest: addressFocusRequest,
                    isCommandPalettePresented: isCommandPalettePresented,
                    isCompact: false,
                    obscuresSystemSafeAreas:
                        usesCollapsedSidebarBorderlessFrame,
                    showsCompactToolbar: false,
                    compactToolbarIsHidden: compactToolbarIsHidden,
                    handleWebContentInteraction: {
                        model.navigation.utilityPresentation
                            .handleInteraction(.webContent)
                        model.navigation.handleRegularPageInteraction()
                    },
                    submitAddress: submitAddress,
                    beginNewTab: beginNewTab,
                    showTabViewer: showTabViewer,
                    hideCompactToolbar: hideCompactToolbar,
                    showCompactToolbar: showCompactToolbar,
                    handleToolbarSwipe: handleToolbarSwipe,
                    selectSplitCard: selectSplitCard,
                    compactTransitionEnded: compactTransitionEnded
                )
            )
            // The lone tab on show is a card as far as a drag is concerned: it
            // is what a dropped tab would join, and the side of it the finger
            // is on is which side of it the new card lands.
            .browserSplitDropCardFrame(
                tabID: singleCardTabID,
                assignment: presentedAssignment,
                state: model.browser.sidebarReorderState
            )
        }
    }

    /// The Space whose cards this window is showing, or `nil` when there are none
    /// to show. A locked Space presents its access gate instead of pages, so it
    /// counts as none.
    private var presentingSpace: BrowserSpace? {
        guard let space = model.browser.selectedSpace,
            !model.spaceAccess.isLocked(space)
        else { return nil }
        return space
    }

    private var presentedAssignment: BrowserSpaceRuntimeAssignment? {
        presentingSpace.map(BrowserSpaceRuntimeAssignment.init(space:))
    }

    /// The cards to lay out as columns, or `nil` for the single-surface path.
    ///
    /// Two things open the columns layout, exactly as on macOS. A group of more
    /// than one member is the obvious one. The other is a drag that has reached
    /// the content area: a window presenting a single tab has to become a
    /// one-card row before it can show a drop placeholder beside that tab, and it
    /// stays one for the rest of the drag rather than following the finger back
    /// and forth — every flip between the two layouts hands the live web view to
    /// a different host, and the placeholder coming and going inside the columns
    /// layout is only a width change.
    private var splitPresentation: (space: BrowserSpace, members: [BrowserTab])? {
        guard let space = presentingSpace else { return nil }
        let members = model.presentedSplitMembers
        guard !members.isEmpty,
            members.count > 1 || isColumnsLayoutHeldOpenByDrag
        else { return nil }
        return (space, members)
    }

    private var isColumnsLayoutHeldOpenByDrag: Bool {
        model.browser.sidebarReorderState.hasEnteredSplitContent
    }

    /// The slot a drag in flight would drop a card into, for this Space.
    private var splitInsertIndex: Int? {
        guard let space = presentingSpace,
            case .splitInsert(let assignment, let index) =
                model.browser.sidebarReorderState.resolvedTarget?.kind,
            assignment.spaceID == space.id
        else { return nil }
        return index
    }

    /// The tab the single surface is showing, when there is one to drop beside.
    private var singleCardTabID: TabID? {
        guard presentingSpace != nil else { return nil }
        return model.browser.selectedTab?.id
    }
}
