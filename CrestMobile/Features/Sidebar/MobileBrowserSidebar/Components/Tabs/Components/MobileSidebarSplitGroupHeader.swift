import SwiftUI

/// The group's affordance: the split glyph and how many tabs are in it.
///
/// It also gives the container's own context menu somewhere to be reached. Every
/// member line carries a menu of its own and together they cover almost the whole
/// container, so without a strip that belongs to the group there would be nowhere
/// to long-press for "Separate All Tabs".
struct MobileSidebarSplitGroupHeader: View {
    let memberCount: Int

    var body: some View {
        HStack(spacing: MobileSidebarSplitGroupRowMetrics.headerSpacing) {
            Image(systemName: "rectangle.split.2x1")
                .font(
                    .system(
                        size: MobileSidebarSplitGroupRowMetrics.headerGlyphSize,
                        weight: .semibold
                    )
                )

            Text(memberCount, format: .number)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .frame(height: MobileSidebarSplitGroupRowMetrics.headerHeight)
        .padding(
            .horizontal,
            MobileSidebarSplitGroupRowMetrics.memberLeadingInset
        )
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Split View with \(memberCount) tabs")
    }
}

#Preview("Mobile Split Group Header", traits: .sizeThatFitsLayout) {
    MobileSidebarSplitGroupHeader(memberCount: 3)
        .frame(width: 320)
        .padding()
}
