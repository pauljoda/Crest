import CoreGraphics

/// Measurements and opacity roles shared by every Crest button treatment.
enum CrestButtonMetrics {
    static let pressedScale: CGFloat = 0.975
    static let disabledOpacity = 0.42

    #if os(macOS)
        static let prominentHeight: CGFloat = 34
        static let standardHeight: CGFloat = 34
    #else
        static let prominentHeight: CGFloat = 44
        static let standardHeight: CGFloat = 44
    #endif
    /// A page's one large call to action, as on Crest's website.
    #if os(macOS)
        static let largeHeight: CGFloat = 50
    #else
        static let largeHeight: CGFloat = 54
    #endif
    static let largeHorizontalPadding: CGFloat = 28
    static let prominentHorizontalPadding: CGFloat = 18
    static let standardHorizontalPadding: CGFloat = 16
    static let quietHorizontalPadding: CGFloat = CrestSpacing.small

    /// The visible icon diameter and its independently accessible hit target.
    static let iconDiameter: CGFloat = 34

    static let strokeWidth: CGFloat = CrestLayout.hairline
    static let quietStrokeWidth: CGFloat = 0.75
    static let prominentStrokeWidth: CGFloat = 1.25

    static let inkStrokeOpacity = CrestBrandTheme.lineLightOpacity
    static let pressedFillOpacity = 0.78
    /// The primary pill at rest, short of full so hovering lifts it.
    static let primaryRestFill = 0.92
    static let sheenOpacity = 0.3
    static let primaryShadowOpacity = 0.18
    static let primaryShadowRadius: CGFloat = 2
    /// The secondary pill's fill at rest, under the pointer and pressed, and
    /// its rim.
    static let quietRestFill = 0.07
    static let quietHoverFill = 0.11
    static let quietPressedFill = 0.16
    static let quietStrokeOpacity = 0.08
    static let tintRestFill = 0.10
    static let tintEmphasizedFill = 0.16
    static let tintPressedFill = 0.22
    static let tintRestStroke = 0.28
    static let tintEmphasizedStroke = 0.55

    static let standardLabelSize: CGFloat = 13
}
