import SwiftUI

/// The group's affordance: the split glyph and how many tabs are in it.
///
/// It earns its place twice over now that members are ordinary tab rows. It is
/// the only thing that says "these rows are one split" before you notice the
/// container behind them — full-height rows otherwise read as neighbours that
/// happen to share a tint. And every member row carries a context menu of its
/// own, together covering all but a 4pt frame of the container, so without a
/// strip that belongs to the group there would be nowhere left to right-click
/// for "Separate All Tabs".
struct SidebarSplitGroupHeader: View {
    let memberCount: Int

    var body: some View {
        HStack(spacing: SidebarSplitGroupRowMetrics.headerSpacing) {
            Image(systemName: "rectangle.split.2x1")
                .font(
                    .system(
                        size: SidebarSplitGroupRowMetrics.headerGlyphSize,
                        weight: .semibold
                    )
                )

            Text(memberCount, format: .number)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .frame(height: SidebarSplitGroupRowMetrics.headerHeight)
        .padding(.horizontal, SidebarSplitGroupRowMetrics.headerLeadingInset)
        .contentShape(.rect)
        // The container announces the group and its member count already; a
        // second element repeating it would only make the run longer to walk.
        .accessibilityHidden(true)
    }
}
