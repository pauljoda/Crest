import SwiftUI

/// Spans a settings form across the whole page, so it scrolls wherever the
/// pointer is and its scroller sits at the page's edge, while scroll-content
/// margins hold its rows to a centred column.
///
/// The margins come from the width the page offers, never the form's own: a
/// row that can't shrink to the column widens the form, and margins measured
/// from it would then move the column under that row on every pass.
///
/// macOS 27 and later only. On macOS 26 horizontal scroll-content margins
/// became scroll-view insets that moved the rows' clicks and accessibility
/// frames a margin away from where they were drawn.
struct BrowserSettingsPageWideColumn: ViewModifier {
    let columnWidth: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .contentMargins(
                    .horizontal,
                    BrowserSettingsLayout.formInset(for: geometry.size.width, columnWidth: columnWidth),
                    for: .scrollContent)
        }
    }
}
