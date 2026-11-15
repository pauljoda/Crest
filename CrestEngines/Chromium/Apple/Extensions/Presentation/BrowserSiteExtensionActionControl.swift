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
        .buttonStyle(
            CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact, showsRestingFill: true)
        )
        // Only running the action waits on the page: an extension it can't
        // run there still opens its menu and can be pinned.
        .disabled(!action.isEnabled)
        .frame(maxWidth: .infinity)
        .overlay {
            BrowserExtensionContextMenuTrigger(presentMenu: presentMenu)
        }
        // VoiceOver reaches the tile here, outside the disabled button, which
        // takes no action at all, so pinning works on any page.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.displayName)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("extension-action-\(action.id)")
        .accessibilityAction {
            guard action.isEnabled else { return }
            perform()
        }
        .accessibilityAction(
            named: action.isPinned ? "Unpin Extension" : "Pin Extension",
            togglePinned
        )
        .help(action.displayName)
    }
}
