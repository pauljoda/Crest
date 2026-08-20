import SwiftUI

/// The outline a collapsed folder wears while releasing would file the lifted
/// item inside it.
///
/// Whether that is what release means is resolved by
/// `BrowserSidebarReorderState` from the measured geometry, so this view takes
/// the answer rather than re-deriving it from a drag session.
struct BrowserFolderNestDropHighlight: View {
    let isTargeted: Bool

    var body: some View {
        if isTargeted {
            RoundedRectangle(
                cornerRadius: CrestLayout.sidebarControlCornerRadius,
                style: .continuous
            )
            .fill(CrestColor.dropIndicator.opacity(0.14))
            .overlay {
                RoundedRectangle(
                    cornerRadius: CrestLayout.sidebarControlCornerRadius,
                    style: .continuous
                )
                .strokeBorder(CrestColor.dropIndicator, lineWidth: 1.5)
            }
            .padding(.horizontal, CrestSpacing.small)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
