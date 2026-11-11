import SwiftUI

struct MobileBrowserDetailSurface: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let isCommandPalettePresented: Bool
    var commands: BrowserCommandPaletteCommandRegistry?
    let isCompact: Bool
    let obscuresSystemSafeAreas: Bool
    let showsCompactToolbar: Bool
    let compactToolbarIsHidden: Bool
    let handleWebContentInteraction: () -> Void
    let submitAddress: () -> Void
    let beginNewTab: () -> Void
    var newTabSearch: (() -> Void)?
    let showTabViewer: () -> Void
    let hideCompactToolbar: () -> Void
    let showCompactToolbar: () -> Void
    let showSwipedTab: (UUID) -> Void
    let compactTransitionEnded: (CGSize) -> Void
    var transientBrowsing: BrowserTransientBrowsingCoordinator?
    var didPromoteTransientPage: () -> Void = {}
    var showHistory: () -> Void = {}
    /// The command palette that rises from the compact address bar, which a
    /// compact window shows there instead of over its page; nil where the bar
    /// edits in place.
    var paletteMode: Binding<BrowserCommandPaletteMode?>?
    /// Opens the palette, as Open Location does.
    var openLocation: (() -> Void)?
    var openPaletteURL: ((BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteMode) -> Bool)?
    var downloadsAssignment: Binding<BrowserSpaceRuntimeAssignment?> = .constant(nil)

    var body: some View {
        MobileBrowserDetailView(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            address: $address,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: addressFocusRequest,
            isCommandPalettePresented: isCommandPalettePresented,
            commands: commands,
            isCompact: isCompact,
            obscuresSystemSafeAreas: obscuresSystemSafeAreas,
            showsCompactToolbar: showsCompactToolbar,
            compactToolbarIsHidden: compactToolbarIsHidden,
            handleWebContentInteraction: handleWebContentInteraction,
            submitAddress: submitAddress,
            beginNewTab: beginNewTab,
            newTabSearch: newTabSearch,
            showTabViewer: showTabViewer,
            hideCompactToolbar: hideCompactToolbar,
            showCompactToolbar: showCompactToolbar,
            showSwipedTab: showSwipedTab,
            compactTransitionEnded: compactTransitionEnded,
            transientBrowsing: transientBrowsing,
            didPromoteTransientPage: didPromoteTransientPage,
            showHistory: showHistory,
            paletteMode: paletteMode,
            openLocation: openLocation,
            openPaletteURL: openPaletteURL,
            downloadsAssignment: downloadsAssignment
        )
    }
}
