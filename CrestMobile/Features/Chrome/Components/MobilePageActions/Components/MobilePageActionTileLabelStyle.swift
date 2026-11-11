import SwiftUI

/// A page menu tile's label: its symbol over its title, filling the tile.
struct MobilePageActionTileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: CrestSpacing.small) {
            configuration.icon
                .font(.title3)
                .frame(height: 24)
            configuration.title
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.horizontal, CrestSpacing.extraSmall)
    }
}
