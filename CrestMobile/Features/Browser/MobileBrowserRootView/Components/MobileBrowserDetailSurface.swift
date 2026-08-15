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
    let showsCompactToolbar: Bool
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
        MobileBrowserDetailView(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            address: $address,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: addressFocusRequest,
            isCommandPalettePresented: isCommandPalettePresented,
            isCompact: isCompact,
            showsCompactToolbar: showsCompactToolbar,
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
    }
}

#Preview("Mobile Browser Detail Surface") {
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    let fixture = MobileBrowserPreviewFixture()

    MobileBrowserDetailSurface(
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: BrowserSpaceAccessController(
            authenticator: MobileBrowserPreviewAuthenticator()
        ),
        address: $address,
        isAddressEditing: $isAddressEditing,
        addressFocusRequest: 0,
        isCommandPalettePresented: false,
        isCompact: true,
        showsCompactToolbar: true,
        compactToolbarIsHidden: false,
        submitAddress: {},
        beginNewTab: {},
        showTabViewer: {},
        hideCompactToolbar: {},
        showCompactToolbar: {},
        handleToolbarSwipe: { _ in },
        selectSplitCard: { _ in },
        compactTransitionEnded: { _ in }
    )
}
