import SwiftUI

/// The single vacant slot under a lifted item. Its real height participates in
/// layout, so surrounding rows and folder surfaces settle around the drop.
struct BrowserSidebarReorderGap: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: CrestRadius.control)
            .fill(.primary.opacity(0.035))
            .padding(.horizontal, CrestSpacing.small)
            .padding(.vertical, CrestSpacing.extraSmall)
            .frame(height: height)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
