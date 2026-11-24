import SwiftUI

struct BrowserUtilitySearchToolbar: View {
    let surface: BrowserUtilitySurface
    @Binding var searchText: String
    @Binding var filter: BrowserUtilityListFilter
    let morphNamespace: Namespace.ID
    /// The identity the toolbar shares with the address field it stands in
    /// for.
    let morph: BrowserCommandSurfaceMorph
    var clearHistory: (() -> Void)?
    var focusRequest = 0
    var consumeFocusRequest: @MainActor (Int, BrowserUtilitySurface) -> Bool = { _, _ in false }

    @FocusState private var isSearchFocused: Bool
    @State private var isMounted = false

    var body: some View {
        HStack(spacing: 6) {
            // As tall as the address field it stands in for.
            CrestSearchField(
                text: $searchText, isFocused: $isSearchFocused, height: BrowserChromeLayout.addressHeight
            ) {
                TextField(String(localized: surface.searchPrompt), text: $searchText)
            }
            .onChange(of: focusRequest) { focusSearchIfRequested() }
            .onAppear {
                isMounted = true
                focusSearchIfRequested()
            }
            .onDisappear { isMounted = false }
            .matchedGeometryEffect(
                id: morph,
                in: morphNamespace,
                properties: .frame,
                anchor: .center,
                isSource: true
            )

            BrowserUtilityFilterMenu(
                surface: surface,
                filter: $filter,
                clearHistory: clearHistory
            )
        }
        .accessibilityElement(children: .contain)
    }

    /// Only a mounted field may consume pending input; acknowledgement prevents replay on a later mount.
    private func focusSearchIfRequested() {
        guard isMounted, consumeFocusRequest(focusRequest, surface) else { return }
        isSearchFocused = true
    }
}

#if DEBUG
    #Preview("Search and filter") {
        @Previewable @State var query = ""
        @Previewable @State var filter: BrowserUtilityListFilter = .all
        @Previewable @Namespace var namespace
        BrowserUtilitySearchToolbar(
            surface: .history, searchText: $query, filter: $filter, morphNamespace: namespace,
            morph: .utilitySearch(spaceID: SessionState.Seed.preview.spaces[0].id),
            clearHistory: {}
        )
        .padding().frame(width: 360)
    }
#endif
