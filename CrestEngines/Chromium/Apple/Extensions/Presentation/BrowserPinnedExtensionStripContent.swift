import SwiftUI

struct BrowserPinnedExtensionStripContent: View {
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
            height: BrowserPinnedExtensionStripLayoutPolicy.height(
                for: actions.count
            )
        )
        .background(
            CrestColor.chromeSurface,
            in: .rect(
                cornerRadius:
                    BrowserPinnedExtensionStripLayoutPolicy.sectionCornerRadius
            )
        )
        .padding(.horizontal, BrowserChromeLayout.sidebarHorizontalInset)
        .padding(
            .bottom,
            BrowserPinnedExtensionStripLayoutPolicy.adjacentSpacing
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned Extensions")
        .accessibilityIdentifier("browser-pinned-extensions")
    }
}
