import SwiftUI

struct BrowserPinnedExtensionActionButton: View {
    let action: BrowserExtensionActionPresentation
    let perform: (BrowserExtensionPopupAnchor?) -> Void
    var presentMenu: (BrowserExtensionPopupAnchor?) -> Void = { _ in }

    @State private var isHovering = false
    @State private var popupAnchor: BrowserExtensionPopupAnchor?

    var body: some View {
        anchoredButton
            .background(
                .quaternary.opacity(isHovering ? 1 : 0),
                in: .rect(cornerRadius: 7)
            )
            .contentShape(.rect)
            .onHover { isHovering = $0 }
    }

    private var anchoredButton: some View {
        actionButton
            .frame(
                width: BrowserPinnedExtensionStripLayoutPolicy.tileSize,
                height: BrowserPinnedExtensionStripLayoutPolicy.tileSize
            )
            .background {
                BrowserExtensionPopupAnchorReader(popupAnchor: $popupAnchor)
            }
            .overlay {
                BrowserExtensionContextMenuTrigger(presentMenu: presentMenu)
            }
    }

    private var actionButton: some View {
        Button(action: performAction) {
            BrowserExtensionActionArtwork(
                action: action,
                glyphSize: BrowserPinnedExtensionStripLayoutPolicy.glyphSize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .accessibilityLabel(action.displayName)
        .accessibilityIdentifier("pinned-extension-action-\(action.id)")
        .help(action.displayName)
    }

    private func performAction() {
        perform(
            popupAnchor?.offsetBy(
                dy: -BrowserPinnedExtensionStripLayoutPolicy.tileSize / 2
                    - BrowserPinnedExtensionStripLayoutPolicy.popupGap
            )
        )
    }
}

#Preview("Pinned Extension Action") {
    BrowserPinnedExtensionActionButton(
        action: BrowserSidebarExtensionPreviewFixture.actions[0],
        perform: { _ in }
    )
    .padding()
}
