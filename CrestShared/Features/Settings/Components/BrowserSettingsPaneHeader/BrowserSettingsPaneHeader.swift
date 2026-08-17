import SwiftUI

/// The one way a settings pane says what it is.
///
/// Both shells use the destination's brand hue, editorial title, and quiet
/// explanatory subtitle. Platform-specific identifier and Dynamic Type behavior
/// remain explicit inputs because each shell has already shipped those contracts.
struct BrowserSettingsPaneHeader: View {
    /// The gap between the serif title and its subtitle.
    static let subtitleSpacing = CrestSpacing.extraSmall

    let destination: BrowserSettingsDestination
    let identifier: String
    let layout: BrowserSettingsPaneHeaderLayout

    var body: some View {
        VStack(spacing: 0) {
            BrowserSettingsPaneHeaderIcon(
                destination: destination,
                layout: layout
            )
            .padding(.bottom, layout.iconSpacing)

            BrowserSettingsPaneHeaderCopy(destination: destination)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.topPadding)
        .padding(.bottom, layout.bottomPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
