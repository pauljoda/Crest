import SwiftUI

struct BrowserPeekActionBar: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let closeAccessibilityLabel: LocalizedStringKey
    let closeHelp: LocalizedStringKey
    let dismiss: () -> Void
    let openInSpace: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        GlassEffectContainer(spacing: BrowserPeekChromePolicy.controlSpacing) {
            HStack(spacing: BrowserPeekChromePolicy.controlSpacing) {
                BrowserPeekCloseButton(
                    accessibilityLabel: closeAccessibilityLabel,
                    help: closeHelp,
                    dismiss: dismiss
                )

                BrowserPeekDestinationControl(
                    spaces: spaces,
                    selectedSpaceID: selectedSpaceID,
                    openInSpace: openInSpace
                )
            }
            .labelStyle(.titleAndIcon)
        }
    }
}
