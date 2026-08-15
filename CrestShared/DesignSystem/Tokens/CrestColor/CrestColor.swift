import SwiftUI

/// Semantic colors for Crest-authored chrome. Space identity colors remain data-driven.
enum CrestColor {
    static let selection = Color.primary.opacity(CrestOpacity.selection)
    static let selectedSurface = selection
    static let chromeSurface = Color.primary.opacity(CrestOpacity.chromeSurface)
    static let pinnedSelectedSurface = selectedSurface
    static let pinnedSelectedBorder = Color.primary.opacity(CrestOpacity.selectedBorder)
    static let hover = Color.primary.opacity(CrestOpacity.hover)
    static let subtleBorder = Color.primary.opacity(CrestOpacity.border)
    static let selectedBorder = Color.primary.opacity(CrestOpacity.selectedBorder)
    static let dropIndicator = CrestBrandPalette.paper.opacity(CrestOpacity.dropIndicator)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
}
