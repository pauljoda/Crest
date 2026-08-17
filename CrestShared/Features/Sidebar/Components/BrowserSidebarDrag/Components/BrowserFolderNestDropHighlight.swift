import SwiftUI

struct BrowserFolderNestDropHighlight: View {
    let location: BrowserFolderDropLocation
    let dragState: BrowserFolderDragState
    let isTargeted: Bool

    var body: some View {
        if isTargeted, dragState.dropLocation == location {
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
