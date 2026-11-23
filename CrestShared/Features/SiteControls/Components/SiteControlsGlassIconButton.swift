import SwiftUI

/// A round icon button on Liquid Glass at a page's corner, such as Back,
/// Edit or Done, with its title as its help and its VoiceOver label. A
/// prominent one, such as Done, stands on Crest blue glass.
struct SiteControlsGlassIconButton: View {
    let title: LocalizedStringResource
    let symbol: String
    var isProminent = false
    let action: () -> Void

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
            }
            .labelStyle(.iconOnly)
            .font(.system(size: metrics.glassIconGlyphSize, weight: .semibold))
            .foregroundStyle(isProminent ? Color.white : CrestColor.textPrimary)
            .frame(width: metrics.glassIconSize, height: metrics.glassIconSize)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .crestGlass(tint: isProminent ? CrestBrandTheme.accent : nil, in: .circle)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}
