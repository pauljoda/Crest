import SwiftUI

/// A pane's identity as one bar-height row: the brand tile and the display
/// serif title, the way the Spaces pane names itself above its toolbar.
///
/// Used where the page has something better to spend its height on than a
/// centred header — a live preview pinned beside the form.
struct BrowserSettingsCompactPageIdentity: View {
    let destination: BrowserSettingsDestination

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            CrestIconTile(
                systemImage: destination.symbol,
                color: destination.color,
                size: 30,
                symbolSize: 13,
                cornerRadius: CrestRadius.control
            )
            .accessibilityHidden(true)

            Text(destination.title)
                .font(CrestTypography.displaySection)
                .foregroundStyle(CrestBrandTheme.textDisplay)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, CrestSpacing.medium)
        .frame(minHeight: 54, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-page-header")
    }
}
