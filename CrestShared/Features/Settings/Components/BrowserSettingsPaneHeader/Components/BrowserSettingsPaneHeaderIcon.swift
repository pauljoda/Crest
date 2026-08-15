import SwiftUI

struct BrowserSettingsPaneHeaderIcon: View {
    let destination: BrowserSettingsDestination
    let layout: BrowserSettingsPaneHeaderLayout

    @ScaledMetric(relativeTo: .title) private var scaledIconSize: CGFloat = 0
    @ScaledMetric(relativeTo: .title) private var scaledSymbolSize: CGFloat = 0

    init(
        destination: BrowserSettingsDestination,
        layout: BrowserSettingsPaneHeaderLayout
    ) {
        self.destination = destination
        self.layout = layout
        _scaledIconSize = ScaledMetric(
            wrappedValue: layout.iconSize,
            relativeTo: .title
        )
        _scaledSymbolSize = ScaledMetric(
            wrappedValue: layout.symbolSize,
            relativeTo: .title
        )
    }

    var body: some View {
        CrestIconTile(
            systemImage: destination.symbol,
            color: destination.color,
            size: iconSize,
            symbolSize: symbolSize,
            cornerRadius: layout.cornerRadius,
            castsShadow: false
        )
        .accessibilityHidden(true)
    }

    private var iconSize: CGFloat {
        layout.scalesIconWithDynamicType ? scaledIconSize : layout.iconSize
    }

    private var symbolSize: CGFloat {
        layout.scalesIconWithDynamicType ? scaledSymbolSize : layout.symbolSize
    }
}

#Preview("Settings Pane Header Icon") {
    BrowserSettingsPaneHeaderIcon(
        destination: .privacy,
        layout: .mobilePage
    )
}
