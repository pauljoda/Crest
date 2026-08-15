import CoreGraphics

/// Artwork and control dimensions unique to the Space-branding forge.
enum BrowserSpaceForgeMetrics {
    static let patternCardMinimumWidth: CGFloat = 108
    static let compactPatternCardMinimumWidth: CGFloat = 96
    static let crestCardMinimumWidth: CGFloat = 90
    static let compactCrestCardMinimumWidth: CGFloat = 82
    static let chargeCardMinimumWidth: CGFloat = 84
    static let compactChargeCardMinimumWidth: CGFloat = 78

    static let patternBannerHeight: CGFloat = 46
    static let crestThumbnailSize: CGFloat = 46
    static let chargeThumbnailSize: CGFloat = 42

    static let bannerArtifactHeight: CGFloat = 172
    static let compactBannerArtifactHeight: CGFloat = 152
    static let crestArtifactSize: CGFloat = 124
    static let compactCrestArtifactSize: CGFloat = 108

    static let previewMaximumWidth: CGFloat = 520
    static let previewHeight: CGFloat = 220
    static let compactPreviewHeight: CGFloat = 190
    static let previewSearchFieldHeight: CGFloat = 34
    static let previewIdentitySize: CGFloat = 40
    static let previewSymbolPointSize: CGFloat = 18

    static let gradientDialSize: CGFloat = 86
    static let compactGradientDialSize: CGFloat = 76
    static let gradientNeedleLengthRatio: CGFloat = 0.37
    static let gradientNeedleThicknessRatio: CGFloat = 0.035
    static let gradientNeedleOffsetRatio: CGFloat = 0.185
    static let gradientNeedleMinimumThickness: CGFloat = 2
    static let gradientCenterDiameterRatio: CGFloat = 0.075
    static let gradientCenterMinimumDiameter: CGFloat = 5
    static let gradientFocusRingWidth: CGFloat = 2
    static let gradientFocusRingInset: CGFloat = 2

    static let chargeLayoutMaximumWidth: CGFloat = 260
    static let presetSwatchHeight: CGFloat = 26
    static let paletteColorDiameter: CGFloat = 26
    static let compactPaletteControlSize: CGFloat = 48
    static let paletteControlSize: CGFloat = 56
    static let compactPaletteMaximumWidth: CGFloat = 92
    static let paletteMaximumWidth: CGFloat = 108
    static let compactPaletteScale: CGFloat = 1.25
    static let paletteScale: CGFloat = 1.4
    static let optionLabelMinimumScale: CGFloat = 0.7
    static let paletteLabelMinimumScale: CGFloat = 0.8

    static let expandedChevronRotation = 90.0
    static let angleCircleDegrees = 360.0
    static let radiansToDegrees = 180.0
    static let normalizedControlRange = 0.0...1.0

    static let gridSpacing: CGFloat = CrestSpacing.small
    static let artworkCornerRadius: CGFloat = CrestRadius.compact
}
