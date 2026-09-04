import SwiftUI

/// The part of a tab row that opens the tab: its favicon, its title, and the
/// whole strip of surface between them and the trailing control.
///
/// Shared with the split-group member lines, which draw the same label at
/// their own insets inside a group's container.
struct BrowserSidebarTabActivationButton: View {
    let tab: BrowserTab
    /// The Space the row is listed in, which is what an extension side panel is
    /// bound against — both for the badge on the favicon and for the panel this
    /// button announces.
    let spaceID: SpaceID
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let metrics: BrowserSidebarTabRowMetrics
    /// The inset the label starts at. Part of the button rather than of the
    /// row, so the strip in front of the favicon opens the tab too. A nested
    /// line leaves it at zero: its container has already placed it.
    var leadingInset: CGFloat = 0
    let restoreSavedLocation: (() -> Void)?
    let iconCustomization: BrowserIconCustomizationPresentation
    let select: () -> Void

    /// Read here rather than inside the badge: the row is an accessibility
    /// container whose one labelled element is this button, so only the value
    /// written at this level is ever spoken. See
    /// `BrowserTabSidePanelAccessibility`.
    @Environment(\.browserTabSidePanel) private var sidePanel

    var body: some View {
        Button(action: select) {
            label
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .contentShape(.rect)
        .overlay(alignment: .leading) {
            Color.clear
                .frame(
                    width: metrics.faviconSlot?.width ?? 18,
                    height: metrics.faviconSlot?.glyphSize ?? 18
                )
                .padding(.leading, leadingInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .browserIconCustomizationPopover(iconCustomization)
        }
        .accessibilityLabel(tab.displayTitle)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(BrowserTabAccessibilityID.row(tab.id))
    }

    /// What the tab is holding, spoken after what the tab is: whether it is
    /// resident, and the extension side panel bound to it where there is one.
    private var accessibilityValue: String {
        BrowserTabSidePanelAccessibility.value(
            BrowserChromeAccessibility.tabValue(isLoaded: isLoaded),
            panelTitle: sidePanel?.sidePanelPresentation(
                forTab: tab.id,
                in: spaceID
            )?.title
        )
    }

    /// The residency treatment sits on the two pieces that describe the tab
    /// rather than on the label as a whole, so the side-panel badge the favicon
    /// carries stays out of it.
    private var label: some View {
        Label {
            Text(tab.displayTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .browserTabResidency(isLoaded: isLoaded)
        } icon: {
            icon
        }
        .padding(.leading, leadingInset)
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .leading)
        .contentShape(.rect)
    }

    private var icon: some View {
        HStack(spacing: 3) {
            BrowserSidebarTabFavicon(
                tab: tab,
                profileID: profileID,
                metrics: metrics,
                isProminent: isSelected,
                isLoaded: isLoaded,
                sidePanelSpaceID: spaceID
            )

            if tab.placement == .saved,
                tab.isAwayFromSavedLocation,
                let restoreSavedLocation
            {
                BrowserTabSavedLocationIndicator(restore: restoreSavedLocation)
                    .browserTabResidency(isLoaded: isLoaded)
            }
        }
    }

    /// A fixed-height row wants its activation area to fill the band; a row
    /// that grows with its label wants no height constraint at all.
    private var maxHeight: CGFloat? {
        metrics.fillsRowHeight ? .infinity : nil
    }
}
