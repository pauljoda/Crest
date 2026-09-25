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

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField(surface.searchPrompt, text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        searchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: BrowserChromeLayout.addressHeight)
            .background(
                CrestColor.chromeSurface,
                in: .rect(cornerRadius: BrowserChromeLayout.addressCornerRadius)
            )
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
}

#if DEBUG
    #Preview("Search and filter") {
        @Previewable @State var query = ""
        @Previewable @State var filter: BrowserUtilityListFilter = .all
        @Previewable @Namespace var namespace
        BrowserUtilitySearchToolbar(
            surface: .history, searchText: $query, filter: $filter, morphNamespace: namespace,
            morph: .utilitySearch(spaceID: BrowserSession.preview.spaces[0].id),
            clearHistory: {}
        )
        .padding().frame(width: 360)
    }
#endif
