import SwiftUI

/// A sidebar's tab preview on an iPhone or iPad: the shared layer, drawing
/// the pictures the scene's pages keep, which it starts them keeping. A
/// pointer resting on a row shows its card beside the sidebar's edge, and a
/// finger holding a folder shows the folder's card over a scrim. Showing
/// another Space takes the card down, and a drag that starts takes a held
/// card down, as the drag is what the hold went on to.
struct MobileTabPreviewLayer: View {
    // MARK: - Variables

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let preview: BrowserTabPreviewState
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    /// How far the sidebar's page edge is from its side of the layer, or nil
    /// where the sidebar fills the layer.
    var sidebarEdge: CGFloat?

    // MARK: - Actions - Presentation

    var body: some View {
        let pictures = pages.tabPictures
        BrowserTabPreviewLayer(preview: preview, sidebarEdge: sidebarEdge) { pictures.previewPicture(of: $0) }
            .onChange(of: pages.browser.shownSpace?.id) { preview.dismiss() }
            .onChange(of: sidebarInteraction.sidebarReorderState.isDragging) { _, isDragging in
                if isDragging, preview.shown?.isHeldByTouch == true { preview.dismiss() }
            }
            .onAppear {
                let spaceAccess = spaceAccess
                pictures.follow { spaceAccess.isLocked($0) }
            }
    }
}
