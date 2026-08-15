import SwiftUI

struct BrowserUtilitySearchToolbar: View {
    let surface: BrowserUtilitySurface
    @Binding var searchText: String
    @Binding var filter: BrowserUtilityListFilter
    let morphNamespace: Namespace.ID
    let morphID: String
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
                id: morphID,
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

#Preview("History Search Toolbar", traits: .fixedLayout(width: 360, height: 60)) {
    @Previewable @State var searchText = "Crest"
    @Previewable @State var filter = BrowserUtilityListFilter.historyPastWeek
    @Previewable @Namespace var namespace

    BrowserUtilitySearchToolbar(
        surface: .history,
        searchText: $searchText,
        filter: $filter,
        morphNamespace: namespace,
        morphID: "utility-search-preview",
        clearHistory: {}
    )
    .padding()
}
