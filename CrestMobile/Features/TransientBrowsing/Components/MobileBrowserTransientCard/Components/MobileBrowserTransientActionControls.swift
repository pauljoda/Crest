import SwiftUI

struct MobileBrowserTransientActionControls: View {
    let model: MobileBrowserTransientOverlayModel
    let dismiss: () -> Void
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        BrowserPeekActionBar(
            spaces: model.availableSpaces,
            selectedSpaceID: model.request.spaceID,
            closeAccessibilityLabel: closeLabel,
            closeHelp: closeHelp,
            dismiss: dismiss,
            openInSpace: promote
        )
    }

    private var closeLabel: LocalizedStringKey {
        model.request.isQuickWindow
            ? "Close Quick Window"
            : "Close Peek"
    }

    private var closeHelp: LocalizedStringKey {
        model.request.isQuickWindow
            ? "Close Quick Window (Esc or ⌘W)"
            : "Close Peek (Esc or ⌘W)"
    }
}
