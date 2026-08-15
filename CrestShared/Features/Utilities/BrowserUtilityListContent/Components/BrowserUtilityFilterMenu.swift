import SwiftUI

struct BrowserUtilityFilterMenu: View {
    let surface: BrowserUtilitySurface
    @Binding var filter: BrowserUtilityListFilter
    var clearHistory: (() -> Void)?

    var body: some View {
        Menu {
            Picker("Filter", selection: $filter) {
                ForEach(BrowserUtilityListFilter.options(for: surface)) { option in
                    Text(option.title).tag(option)
                }
            }

            if let clearHistory, surface == .history {
                Divider()
                Button("Clear History", systemImage: "trash", role: .destructive) {
                    clearHistory()
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .frame(
                    width: BrowserUtilitySwitcherLayout.buttonSize,
                    height: BrowserChromeLayout.addressHeight
                )
                .contentShape(.rect)
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .modifier(BrowserPlatformUtilityFilterMenuStyle())
        .help(Text(surface.filterLabel))
        .accessibilityLabel(Text(surface.filterLabel))
        .accessibilityValue(Text(filter.normalized(for: surface).title))
        .accessibilityIdentifier("utility-filter-button")
    }
}

#Preview("Download Filter Menu", traits: .fixedLayout(width: 80, height: 64)) {
    @Previewable @State var filter = BrowserUtilityListFilter.downloadsInProgress

    BrowserUtilityFilterMenu(
        surface: .downloads,
        filter: $filter
    )
    .padding()
}
