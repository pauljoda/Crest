import SwiftUI

struct BrowserPeekActionBar: View {
    // MARK: - Static Variables

    private static let openControlWidth: CGFloat = 206
    private static let controlSpacing: CGFloat = 10

    /// The bar beside a pointer's card: the X and Open In at its own width.
    static var width: CGFloat {
        BrowserPeekControlStyle.actionBar.height + controlSpacing + openControlWidth
    }

    /// The widest a bar under a thumb grows, Open In taking the room the X
    /// leaves it.
    static let maximumWidth: CGFloat = 422

    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let closeAccessibilityLabel: LocalizedStringKey
    let closeHelp: LocalizedStringKey
    let dismiss: () -> Void
    let openInSpace: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        // Close and Open In stay two pieces of glass, so Open In keeps its
        // Space's tint rather than blending into Close's.
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: Self.controlSpacing) {
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
