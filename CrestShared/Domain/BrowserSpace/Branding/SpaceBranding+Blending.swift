import Foundation

/// A look partway to another, for a look that changes in front of the person
/// rather than switching: every color the wells hold mixed toward the other's
/// and the texture eased toward its strength, so each surface that draws them,
/// a material over the sidebar included, changes with the rest. What cannot
/// mix, such as the crest's parts or the sidebar's pattern, is the first
/// look's until halfway and the other's after.
extension SpaceBranding {
    // MARK: - Functions

    /// This look `amount` of the way, from 0 to 1, toward `other`.
    func blended(toward other: SpaceBranding, by amount: Double) -> SpaceBranding {
        var look = amount < 0.5 ? self : other
        let background = backgroundFill.blended(toward: other.backgroundFill, by: amount)
        let accent = accentFill.blended(toward: other.accentFill, by: amount)
        let pattern = patternFill.blended(toward: other.patternFill, by: amount)
        look.backgroundFill = background
        look.accentFill = accent
        look.patternFill = pattern
        look.textureStrength = textureStrength + (other.textureStrength - textureStrength) * amount
        return look
    }
}
