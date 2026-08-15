import SwiftUI

struct BrowserSiteExtensionsSection: View {
    let actions: [BrowserExtensionActionPresentation]
    let manageExtensions: () -> Void
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    let togglePinned: (BrowserExtensionActionPresentation) -> Void
    var presentMenu:
        (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) ->
            Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserSiteExtensionsHeader(
                manageExtensions: manageExtensions
            )
            if actions.isEmpty {
                Label(
                    "No extension actions for this page",
                    systemImage: "puzzlepiece.extension"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                actionGrid
            }
        }
    }

    private var actionGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(
                    .flexible(),
                    spacing: BrowserSiteControlLayoutPolicy.extensionGridSpacing
                ),
                count: BrowserSiteControlLayoutPolicy.extensionColumnCount
            ),
            spacing: BrowserSiteControlLayoutPolicy.extensionGridSpacing
        ) {
            ForEach(actions) { action in
                BrowserSiteExtensionActionButton(
                    action: action,
                    perform: { perform(action, $0) },
                    togglePinned: { togglePinned(action) },
                    presentMenu: { presentMenu(action, $0) }
                )
            }
        }
    }
}

#Preview("Site Extension Actions") {
    BrowserSiteExtensionsSection(
        actions: BrowserSidebarExtensionPreviewFixture.actions,
        manageExtensions: {},
        perform: { _, _ in },
        togglePinned: { _ in }
    )
    .padding()
    .frame(width: BrowserSiteControlLayoutPolicy.width)
}
