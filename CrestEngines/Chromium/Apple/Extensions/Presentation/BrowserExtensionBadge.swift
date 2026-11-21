import SwiftUI

/// The count or word an extension shows on its action, on Crest's red, as a
/// download badge needing attention is.
struct BrowserExtensionBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(CrestTypography.badge)
            .lineLimit(1)
            .browserReadableForeground(over: CrestColor.danger)
            .padding(.horizontal, BrowserExtensionsMetrics.badgeHorizontalPadding)
            .frame(
                minWidth: BrowserExtensionsMetrics.badgeMinimumSize,
                minHeight: BrowserExtensionsMetrics.badgeMinimumSize
            )
            .fixedSize()
            .background(CrestColor.danger, in: .capsule)
            .offset(x: BrowserExtensionsMetrics.badgeOffset, y: -BrowserExtensionsMetrics.badgeOffset)
    }
}

#if DEBUG
    #Preview("Badge lengths") {
        HStack(spacing: 20) {
            BrowserExtensionBadge(text: "3")
            BrowserExtensionBadge(text: "99+")
        }.padding()
    }
#endif
