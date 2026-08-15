import SwiftUI

/// The one root view the drag preview window hosts, whichever kind of thing is
/// travelling on the pointer.
///
/// It exists so the host owns a single `NSHostingView` for the life of a window
/// rather than a generic one per kind of lift: the panel, the hosting view, and
/// the appearance are the same machinery for a sidebar row and for a Split View
/// card, and only the art differs. Each case is that feature's own preview,
/// unchanged by being drawn somewhere else.
struct BrowserDragPreviewWindowFloatingContent: View {
    let content: BrowserDragPreviewWindowContent

    var body: some View {
        switch content {
        case .sidebarLift(let sidebar):
            BrowserSidebarLiftFloatingPreview(
                subject: sidebar.subject,
                lift: sidebar.lift,
                reduceMotion: sidebar.reduceMotion
            )
        case .splitCardLift(let card):
            BrowserSplitCardLiftFloatingPreview(content: card)
        }
    }
}

#Preview("Drag Preview Window Floating Content", traits: .fixedLayout(width: 620, height: 460)) {
    BrowserDragPreviewWindowFloatingContent(
        content: .splitCardLift(
            BrowserSplitCardLiftPreviewContent(
                tab: BrowserSplitViewPreviewFixture.members[0],
                profileID: BrowserSplitViewPreviewFixture.profileID,
                snapshot: nil,
                origin: CGPoint(x: 70, y: 50),
                size: CGSize(width: 420, height: 340),
                grabFraction: CGPoint(x: 0.5, y: 0.15),
                isSettling: false,
                reduceMotion: false
            )
        )
    )
    .background(CrestBrandTheme.canvas)
}
