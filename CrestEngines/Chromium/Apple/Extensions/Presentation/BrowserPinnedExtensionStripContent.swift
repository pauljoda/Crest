import SwiftUI

struct BrowserPinnedExtensionStripContent: View {
    // MARK: - Static Variables

    private static let sectionHeight: CGFloat = 32

    // MARK: - Variables

    let actions: [BrowserExtensionActionPresentation]
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    var prepare: (BrowserExtensionActionPresentation) -> Void = { _ in }
    var presentMenu:
        (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) ->
            Void = { _, _ in }
    /// How the tiles move, or nil for a strip that keeps its order.
    var reordering: BrowserPinnedExtensionActionList.Reordering?
    /// The Space whose strip this is.
    var spaceID: UUID?

    var body: some View {
        BrowserPinnedExtensionActionList(
            actions: actions,
            perform: perform,
            prepare: prepare,
            presentMenu: presentMenu,
            reordering: reordering,
            spaceID: spaceID
        )
        .frame(
            height: actions.count > 0 ? Self.sectionHeight : 0
        )
        .background {
            CrestSurfaceLayer(
                shape: .rect(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous))
        }
        // The same scheme as the address field and the pins around it.
        .modifier(SurfaceToneAppearance())
        .padding(.horizontal, BrowserSidebarMetrics.layerInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned Extensions")
        .accessibilityIdentifier("browser-pinned-extensions")
    }
}
