import Foundation

enum BrowserFolderAppearancePolicy {
    static let regionInset = BrowserFolderLayout.contentsInset / 2
    static let frontHighlightOpacity = 0.12

    /// The artwork's white highlight composited over its front face, including
    /// translucent custom colors. Titles use the same resolved shade.
    static func frontColor(_ color: BrowserSpaceBrandColor) -> BrowserSpaceBrandColor {
        let baseAlpha = color.alpha * (1 - frontHighlightOpacity)
        let alpha = baseAlpha + frontHighlightOpacity
        return BrowserSpaceBrandColor(
            red: (color.red * baseAlpha + frontHighlightOpacity) / alpha,
            green: (color.green * baseAlpha + frontHighlightOpacity) / alpha,
            blue: (color.blue * baseAlpha + frontHighlightOpacity) / alpha,
            alpha: alpha)
    }

    static func compositedColor(_ color: BrowserSpaceBrandColor, opacity: Double, background: BrowserSpaceBrandColor)
        -> BrowserSpaceBrandColor
    {
        let alpha = color.alpha * opacity
        return BrowserSpaceBrandColor(
            red: color.red * alpha + background.red * (1 - alpha),
            green: color.green * alpha + background.green * (1 - alpha),
            blue: color.blue * alpha + background.blue * (1 - alpha))
    }

    static func showsFill(alwaysVisible: Bool, isHovered: Bool, isTargeted: Bool) -> Bool {
        alwaysVisible || isHovered || isTargeted
    }

    static func fillOpacity(intensity: Double, reduceTransparency: Bool) -> Double {
        let strength = intensity.isFinite ? min(max(intensity, 0), 1) : 0
        let baseline = reduceTransparency ? 0.28 : 0.12
        return baseline + (1 - baseline) * strength
    }
}
