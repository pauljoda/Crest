import SwiftUI

/// Shared selectable surface for callers with custom card content.
struct CrestSelectableCardStyle: ButtonStyle {
    let isSelected: Bool
    var density = CrestSelectableCardDensity.regular
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        CrestSelectableCardSurface(
            isSelected: isSelected,
            density: density,
            tint: tint,
            configuration: configuration
        )
    }
}
