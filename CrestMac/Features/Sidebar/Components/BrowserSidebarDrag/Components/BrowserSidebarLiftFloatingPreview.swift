import SwiftUI

/// The whole of what the drag preview window shows: one lifted row, drawn at the
/// pointer, over nothing.
///
/// A full-bleed layer rather than a view sized to the preview, because its host
/// is a window pinned to the browser window's own bounds: placing the preview by
/// its top-left inside that layer puts it exactly where the same lift would have
/// been drawn in the view tree, in the same global coordinates the drag already
/// reports.
///
/// The art is the sidebar's own drag art — a tab morphing between its row, the
/// pinned tile, and the page-shaped card; a folder row; a stack of split-group
/// member lines — so moving where a lift is drawn changed nothing about what it
/// looks like.
///
/// Everything it needs arrives as a value. It reads no drag state, resolves no
/// tab, and owns no window; the host observes the reorder state and hands the
/// result down, which is what keeps a preview drawn in a second window a
/// presentation of the one drag rather than a copy of it.
struct BrowserSidebarLiftFloatingPreview: View {
    let subject: BrowserSidebarLiftPreviewSubject
    let lift: BrowserSidebarFloatingLift
    /// Passed in rather than read from the environment: this view is hosted in a
    /// window of its own, which inherits nothing from the browser's.
    var reduceMotion = false

    var body: some View {
        let origin = lift.origin
        ZStack(alignment: .topLeading) {
            Color.clear
            art
                // Scale before offset, so the rise happens about the preview's
                // own centre and does not shift where the pointer holds it.
                .scaleEffect(BrowserSidebarReorderVisuals.liftScale)
                .offset(x: origin.x, y: origin.y)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Only the shape settles. Animating the position as well would make the
        // preview lag the pointer, which is the one thing a lift must never do.
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.dragPreview,
                reduceMotion: reduceMotion
            ),
            value: lift.shape
        )
        // The window behind this is transparent and click-through; this makes
        // certain nothing in the preview claims a hit test of its own.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var art: some View {
        switch subject {
        case .tab(let tab):
            BrowserTabDragPreview(
                tab: tab,
                profileID: lift.profileID,
                targetShape: lift.shape,
                progress: lift.progress,
                rowWidth: lift.rowWidth
            )
        case .folder(let folder):
            BrowserFolderDragPreview(folder: folder, rowWidth: lift.rowWidth)
        case .splitGroup(let members):
            BrowserSplitGroupDragPreview(
                members: members,
                profileID: lift.profileID,
                rowWidth: lift.rowWidth
            )
        }
    }
}

#Preview("Sidebar Lift Floating Preview", traits: .fixedLayout(width: 620, height: 420)) {
    let fixture = BrowserSidebarInteractionPreviewFixture()

    BrowserSidebarLiftFloatingPreview(
        subject: .tab(fixture.currentTab),
        lift: BrowserSidebarFloatingLift(
            item: .tab(
                BrowserTabDragItem(
                    tabID: fixture.currentTab.id,
                    spaceID: fixture.space.id,
                    profileID: fixture.space.profile.id
                )
            ),
            shape: .webpageCard,
            progress: 1,
            pointer: CGPoint(x: 310, y: 210),
            grabOffset: CGSize(width: 40, height: 20),
            rowWidth: BrowserTabDragPreviewLayout.rowSize.width
        )
    )
    .background(CrestBrandTheme.canvas)
}
