import SwiftUI

struct BrowserCrestImportPinnedGrid: View {
    let space: BrowserSpace
    let matchedTabIDs: Set<TabID>

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(space.pinnedTabs) { tab in
                let isMatched = matchedTabIDs.contains(tab.id)
                TabFaviconView(
                    tab: tab,
                    profileID: space.profile.id,
                    size: 19
                )
                .frame(maxWidth: .infinity)
                .frame(height: 47)
                .background(
                    isMatched
                        ? BrowserOnboardingPalette.match.opacity(0.2)
                        : Color.primary.opacity(
                            tab.id == space.selectedTabID ? 0.14 : 0.075
                        ),
                    in: .rect(cornerRadius: 10, style: .continuous)
                )
                .overlay(alignment: .topTrailing) {
                    if isMatched {
                        Image(systemName: "equal.circle.fill")
                            .font(.caption)
                            .foregroundStyle(BrowserOnboardingPalette.match)
                            .padding(4)
                    }
                }
                .overlay {
                    if isMatched {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                BrowserOnboardingPalette.match.opacity(0.64),
                                lineWidth: 1
                            )
                    }
                }
                .accessibilityLabel(tab.title)
                .accessibilityValue(isMatched ? "Matched in source browser" : "In Crest")
            }
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: PinnedTabGridLayout.columnCount(for: space.pinnedTabs.count)
        )
    }
}
