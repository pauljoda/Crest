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

#Preview("Folder Nest Drop Highlight", traits: .fixedLayout(width: 300, height: 60)) {
    let fixture = BrowserSidebarInteractionPreviewFixture()
    let location = BrowserFolderDropLocation(
        parentID: fixture.folder.id,
        beforeSiblingID: nil
    )
    let dragState = fixture.makeFolderDragState(dropLocation: location)

    BrowserFolderNestDropHighlight(
        location: location,
        dragState: dragState,
        isTargeted: true
    )
}
