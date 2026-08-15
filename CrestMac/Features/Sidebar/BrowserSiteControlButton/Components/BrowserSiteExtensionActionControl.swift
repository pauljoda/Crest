import SwiftUI

struct BrowserSiteExtensionActionControl: View {
    let action: BrowserExtensionActionPresentation
    let perform: () -> Void
    let togglePinned: () -> Void
    var presentMenu: (BrowserExtensionPopupAnchor?) -> Void = { _ in }

    var body: some View {
        Button(action: perform) {
            BrowserSiteExtensionActionLabel(action: action)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .overlay {
            BrowserExtensionContextMenuTrigger(presentMenu: presentMenu)
        }
        .disabled(!action.isEnabled)
        .accessibilityLabel(action.displayName)
        .accessibilityIdentifier("extension-action-\(action.id)")
        .accessibilityAction(
            named: action.isPinned ? "Unpin Extension" : "Pin Extension",
            togglePinned
        )
        .help(action.displayName)
    }
}

#Preview("Site Extension Action Control") {
    BrowserSiteExtensionActionControl(
        action: BrowserSidebarExtensionPreviewFixture.actions[0],
        perform: {},
        togglePinned: {}
    )
    .padding()
    .frame(width: 72)
}
