import SwiftUI

struct MobileBrowserDetailSurface: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let isCommandPalettePresented: Bool
    let isCompact: Bool
    let obscuresSystemSafeAreas: Bool
    let showsCompactToolbar: Bool
    let compactToolbarIsHidden: Bool
    let handleWebContentInteraction: () -> Void
    let submitAddress: () -> Void
    let beginNewTab: () -> Void
    let showTabViewer: () -> Void
    let hideCompactToolbar: () -> Void
    let showCompactToolbar: () -> Void
    let handleToolbarSwipe: (BrowserSpaceSwipeDirection) -> Void
    let selectSplitCard: (TabID) -> Void
    let compactTransitionEnded: (CGSize) -> Void

    var body: some View {
        MobileBrowserDetailView(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            address: $address,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: addressFocusRequest,
            isCommandPalettePresented: isCommandPalettePresented,
            isCompact: isCompact,
            obscuresSystemSafeAreas: obscuresSystemSafeAreas,
            showsCompactToolbar: showsCompactToolbar,
            compactToolbarIsHidden: compactToolbarIsHidden,
            handleWebContentInteraction: handleWebContentInteraction,
            submitAddress: submitAddress,
            beginNewTab: beginNewTab,
            showTabViewer: showTabViewer,
            hideCompactToolbar: hideCompactToolbar,
            showCompactToolbar: showCompactToolbar,
            handleToolbarSwipe: handleToolbarSwipe,
            selectSplitCard: selectSplitCard,
            compactTransitionEnded: compactTransitionEnded
        )
    }
}
