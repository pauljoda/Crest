import SwiftUI

struct BrowserFolderDropIndicator: View {
    let location: BrowserFolderDropLocation
    let dragState: BrowserFolderDragState
    let isTargeted: Bool

    var body: some View {
        if isTargeted, dragState.dropLocation == location {
            Capsule()
                .fill(CrestColor.dropIndicator)
                .frame(height: 2)
                .padding(.horizontal, CrestSpacing.large)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Folder Drop Indicator", traits: .fixedLayout(width: 300, height: 60)) {
    let fixture = BrowserSidebarInteractionPreviewFixture()
    let dragState = fixture.makeFolderDragState(
        dropLocation: fixture.folderDropLocation
    )

    BrowserFolderDropIndicator(
        location: fixture.folderDropLocation,
        dragState: dragState,
        isTargeted: true
    )
    .padding()
}
