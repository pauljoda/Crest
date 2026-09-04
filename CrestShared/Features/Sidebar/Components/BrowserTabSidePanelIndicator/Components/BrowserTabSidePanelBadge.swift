import SwiftUI

/// The mark a pinned tile carries while an extension side panel is bound to its
/// tab.
///
/// A pinned tile has no label to set a mark beside, so this rides the favicon's
/// bottom-trailing corner instead. It is drawn on its own disc, over the
/// window's ground rather than over the icon: a favicon can be any colour, and
/// the mark has to stay readable against all of them.
///
/// The badge says nothing to VoiceOver: a tile is one button, and the grid
/// writes that button's label and value, so anything declared in here would be
/// merged away. `BrowserTabSidePanelAccessibility` puts the panel into the
/// tile's value instead.
///
/// A shell without extensions supplies no resolver and this draws nothing.
struct BrowserTabSidePanelBadge: View {
    let tabID: TabID
    let spaceID: SpaceID

    @Environment(\.browserTabSidePanel) private var sidePanel

    @ViewBuilder
    var body: some View {
        if let presentation = sidePanel?.sidePanelPresentation(forTab: tabID, in: spaceID) {
            BrowserTabSidePanelArtwork(
                icon: presentation.icon,
                size: BrowserTabSidePanelIndicatorMetrics.badgeArtworkSize
            )
            .frame(width: diameter, height: diameter)
            .background(CrestColor.chromeSurface, in: .circle)
            .background(.background, in: .circle)
            .overlay {
                Circle()
                    .strokeBorder(CrestColor.subtleBorder, lineWidth: CrestLayout.hairline)
            }
            .offset(
                x: BrowserTabSidePanelIndicatorMetrics.badgeOffset,
                y: BrowserTabSidePanelIndicatorMetrics.badgeOffset
            )
            .accessibilityHidden(true)
            .help(Text(verbatim: presentation.title))
        }
    }

    private var diameter: CGFloat {
        BrowserTabSidePanelIndicatorMetrics.badgeDiameter
    }
}
