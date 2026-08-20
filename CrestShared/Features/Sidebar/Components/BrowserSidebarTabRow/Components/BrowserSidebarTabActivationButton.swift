import SwiftUI

/// The part of a tab row that opens the tab: its favicon, its title, and the
/// whole strip of surface between them and the trailing control.
///
/// Shared with the split-group member lines, which draw the same label at
/// their own insets inside a group's container.
struct BrowserSidebarTabActivationButton: View {
    let tab: BrowserTab
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let metrics: BrowserSidebarTabRowMetrics
    /// The inset the label starts at. Part of the button rather than of the
    /// row, so the strip in front of the favicon opens the tab too. A nested
    /// line leaves it at zero: its container has already placed it.
    var leadingInset: CGFloat = 0
    let restoreSavedLocation: (() -> Void)?
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            label
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .contentShape(.rect)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityValue(
            BrowserChromeAccessibility.tabValue(isLoaded: isLoaded)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(BrowserTabAccessibilityID.row(tab.id))
    }

    private var label: some View {
        Label {
            Text(tab.displayTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
        } icon: {
            icon
        }
        .saturation(
            BrowserVisualAccessibilityPolicy.tabResidencySaturation(
                isLoaded: isLoaded
            )
        )
        .opacity(
            BrowserVisualAccessibilityPolicy.tabResidencyOpacity(
                isLoaded: isLoaded
            )
        )
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
                isProminent: isSelected
            )

            if tab.placement == .saved,
                tab.isAwayFromSavedLocation,
                let restoreSavedLocation
            {
                BrowserTabSavedLocationIndicator(restore: restoreSavedLocation)
            }
        }
    }

    /// A fixed-height row wants its activation area to fill the band; a row
    /// that grows with its label wants no height constraint at all.
    private var maxHeight: CGFloat? {
        metrics.fillsRowHeight ? .infinity : nil
    }
}
