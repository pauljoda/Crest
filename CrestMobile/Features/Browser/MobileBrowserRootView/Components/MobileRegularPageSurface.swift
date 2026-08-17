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
struct MobileRegularPageSurface: View {
    let model: MobileBrowserRootModel
    let adjoinsLeadingSidebar: Bool
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
        if let splitPresentation {
            MobileSplitColumnsPageSurface(
                model: model,
                space: splitPresentation.space,
                members: splitPresentation.members,
                adjoinsLeadingSidebar: adjoinsLeadingSidebar
            )
        } else {
            MobileRegularDetailSurface(
                adjoinsLeadingSidebar: adjoinsLeadingSidebar,
                isStartPage: model.browser.selectedTab?.isStartPage == true,
                hasActivePage: model.selectedPage != nil,
                hasSelectedSpace: model.browser.selectedSpace != nil,
                handleWebContentInteraction: {
                    model.navigation.utilityPresentation
                        .handleInteraction(.webContent)
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
                    showsCompactToolbar: false,
                    compactToolbarIsHidden: compactToolbarIsHidden,
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
        }
    }

    private var splitPresentation: (space: BrowserSpace, members: [BrowserTab])? {
        guard let space = model.browser.selectedSpace,
            !model.spaceAccess.isLocked(space)
        else { return nil }
        let members = model.presentedSplitMembers
        guard members.count > 1 else { return nil }
        return (space, members)
    }
}
