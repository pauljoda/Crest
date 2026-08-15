import SwiftUI

extension View {
    /// Lets a section's run draw its own insertion line while it holds no rows.
    func browserSidebarReorderSectionIndicator(
        _ section: BrowserSidebarReorderSection,
        state: BrowserSidebarReorderState
    ) -> some View {
        modifier(
            BrowserSidebarReorderSectionIndicatorModifier(
                section: section,
                state: state
            )
        )
    }
}
