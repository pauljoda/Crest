import SwiftUI

struct BrowserPinnedExtensionStripContent: View {
    // MARK: - Static Variables

    /// The gap between the strip and the sidebar content beside it.
    static let adjacentSpacing = CrestSpacing.small
    private static let sectionHeight: CGFloat = 32
    private static let sectionCornerRadius = BrowserChromeLayout.addressCornerRadius

    // MARK: - Variables

    let actions: [BrowserExtensionActionPresentation]
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    var prepare: (BrowserExtensionActionPresentation) -> Void = { _ in }
    var presentMenu:
        (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) ->
            Void = { _, _ in }

    var body: some View {
        BrowserPinnedExtensionActionList(
            actions: actions,
            perform: perform,
            prepare: prepare,
            presentMenu: presentMenu
        )
        .frame(
            height: actions.count > 0 ? Self.sectionHeight : 0
        )
        .background(
            CrestColor.chromeSurface,
            in: .rect(
                cornerRadius: Self.sectionCornerRadius
            )
        )
        .padding(.horizontal, BrowserChromeLayout.sidebarHorizontalInset)
        .padding(
            .bottom,
            Self.adjacentSpacing
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned Extensions")
        .accessibilityIdentifier("browser-pinned-extensions")
    }
}
