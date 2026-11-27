import SwiftUI

/// Gives a scrolling sidebar list a region at least as tall as its viewport and
/// draws `background` only in the room the list leaves below its rows.
///
/// The background is the sidebar's empty space: on the Mac it moves the window
/// and offers the Space's actions, and a double-click or double-tap there opens
/// a new tab. Behind the rows it would also take the gaps and dividers between
/// the list's sections, such as the line between saved and current tabs. The
/// list's height is measured only as it changes, which scrolling never does.
struct BrowserSidebarRemainderBackground<Background: View>: ViewModifier {
    // MARK: - Variables

    /// The height of the scroll view the list fills.
    let viewportHeight: CGFloat
    @ViewBuilder let background: () -> Background

    @State private var listHeight: CGFloat = 0

    // MARK: - Actions - Drawing

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                listHeight = height
            }
            .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
            .background(alignment: .bottom) {
                background()
                    .frame(maxWidth: .infinity)
                    .frame(height: max(0, viewportHeight - listHeight))
            }
    }
}

extension View {
    /// Fills a scrolling sidebar list's viewport and draws `background` in the
    /// room below its rows. See `BrowserSidebarRemainderBackground`.
    func sidebarRemainderBackground(
        viewportHeight: CGFloat, @ViewBuilder _ background: @escaping () -> some View
    ) -> some View {
        modifier(BrowserSidebarRemainderBackground(viewportHeight: viewportHeight, background: background))
    }
}
