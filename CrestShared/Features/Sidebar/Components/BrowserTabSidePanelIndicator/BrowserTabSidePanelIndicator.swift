import SwiftUI

/// The mark a sidebar tab row carries while an extension side panel is bound to
/// that tab.
///
/// It takes a slot of its own between the row's label and the trailing close
/// control rather than sharing the trailing edge with it. The close control
/// already reserves its frame whether or not hover has revealed it, so a mark
/// placed in front of it rests at one fixed position: nothing shifts when the
/// pointer arrives or leaves, and the two can never overlap. The label is the
/// only part of the row that flexes, so a long title is what gives way when the
/// sidebar narrows.
///
/// A shell without extensions supplies no resolver and this draws nothing —
/// including no empty frame, so the row it sits in is unchanged.
struct BrowserTabSidePanelIndicator: View {
    let tabID: TabID
    let spaceID: SpaceID

    @Environment(\.browserTabSidePanel) private var sidePanel

    @ViewBuilder
    var body: some View {
        if let presentation = sidePanel?.sidePanelPresentation(forTab: tabID, in: spaceID) {
            BrowserTabSidePanelArtwork(
                icon: presentation.icon,
                size: BrowserTabSidePanelIndicatorMetrics.rowArtworkSize
            )
            .padding(.leading, BrowserTabSidePanelIndicatorMetrics.rowSpacing)
            .accessibilityElement()
            .accessibilityLabel(BrowserTabSidePanelAccessibility.title)
            .accessibilityValue(Text(verbatim: presentation.title))
            .help(Text(verbatim: presentation.title))
        }
    }
}
