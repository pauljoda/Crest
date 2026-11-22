import SwiftUI

struct BrowserSiteExtensionActionControl: View {
    let action: BrowserExtensionActionPresentation
    let perform: () -> Void
    let togglePinned: () -> Void
    var presentMenu: (BrowserExtensionPopupAnchor?) -> Void = { _ in }

    /// Whether the action can run now, as the pinned tile decides: the page
    /// allows it and the extension has finished loading.
    private var canRun: Bool { action.isEnabled && !action.isLoading }

    var body: some View {
        Button(action: perform) {
            BrowserSiteExtensionActionLabel(action: action)
        }
        .buttonStyle(
            CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact, showsRestingFill: true)
        )
        // Only running the action waits on the page and on the extension
        // loading: an extension it can't run there still opens its menu and
        // can be pinned.
        .disabled(!canRun)
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
            guard canRun else { return }
            perform()
        }
        .accessibilityAction(
            named: action.isPinned ? "Unpin Extension" : "Pin Extension",
            togglePinned
        )
        .help(action.displayName)
    }
}
