import SwiftUI

/// The mark a tab carries while an extension side panel is bound to it.
///
/// It rides the favicon's bottom-trailing corner, on its own disc drawn over
/// the window's ground rather than over the icon: a favicon can be any colour,
/// and the mark has to stay readable against all of them. A sidebar row and a
/// pinned tile draw exactly this, at exactly this size — the badge belongs to
/// the tab's icon, not to the shape the shell happens to be listing it in, so
/// pinning a tab changes nothing about how its panel is marked.
///
/// The badge says nothing to VoiceOver. A tile is one button and a row is a
/// container with one labelled button in it, and both have their value written
/// from outside, so anything declared in here would be merged away or read
/// twice over. `BrowserTabSidePanelAccessibility` composes those values
/// instead.
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
                x: BrowserTabSidePanelIndicatorMetrics.badgeOverhang,
                y: BrowserTabSidePanelIndicatorMetrics.badgeOverhang
            )
            .accessibilityHidden(true)
            .help(Text(verbatim: presentation.title))
        }
    }

    private var diameter: CGFloat {
        BrowserTabSidePanelIndicatorMetrics.badgeDiameter
    }
}
