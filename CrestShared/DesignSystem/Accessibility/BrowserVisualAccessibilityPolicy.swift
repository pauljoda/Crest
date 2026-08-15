import SwiftUI

/// Centralizes Crest-authored visual effects that must respond to the system's
/// accessibility settings. Native SwiftUI glass remains system-owned; this
/// policy only governs Crest's decorative atmosphere, custom scrims, spatial
/// transforms, and explicit animation transactions.
enum BrowserVisualAccessibilityPolicy {
    private static let reducedTransparencyScrimOpacity = 0.56
    static var tabCloseForeground: Color { .primary }

    static func tabResidencySaturation(isLoaded: Bool) -> Double {
        isLoaded ? 1 : 0.3
    }

    static func tabResidencyOpacity(isLoaded: Bool) -> Double {
        isLoaded ? 1 : 0.5
    }

    static func atmosphereOpacity(
        _ opacity: Double,
        reduceTransparency: Bool
    ) -> Double {
        reduceTransparency ? 0 : opacity
    }

    static func scrimOpacity(
        _ opacity: Double,
        reduceTransparency: Bool
    ) -> Double {
        reduceTransparency
            ? max(opacity, reducedTransparencyScrimOpacity)
            : opacity
    }

    static func spatialScale(
        _ scale: CGFloat,
        reduceMotion: Bool
    ) -> CGFloat {
        reduceMotion ? 1 : scale
    }

    static func spatialOffset(
        _ offset: CGFloat,
        reduceMotion: Bool
    ) -> CGFloat {
        reduceMotion ? 0 : offset
    }

    static func animation(
        _ animation: Animation,
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func readableForeground(
        over background: Color,
        colorScheme: ColorScheme
    ) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        return readableForeground(over: background, environment: environment)
    }

    static func readableForeground(
        over background: Color,
        environment: EnvironmentValues
    ) -> Color {
        let blackRatio = contrastRatio(
            foreground: .black,
            background: background,
            environment: environment
        )
        let whiteRatio = contrastRatio(
            foreground: .white,
            background: background,
            environment: environment
        )
        return blackRatio >= whiteRatio ? .black : .white
    }

    static func contrastRatio(
        foreground: Color,
        background: Color,
        colorScheme: ColorScheme
    ) -> Double {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        return contrastRatio(
            foreground: foreground,
            background: background,
            environment: environment
        )
    }

    static func contrastRatio(
        foreground: Color,
        background: Color,
        environment: EnvironmentValues
    ) -> Double {
        let resolvedForeground = foreground.resolve(in: environment)
        let resolvedBackground = background.resolve(in: environment)
        let backgroundLuminance = relativeLuminance(of: resolvedBackground)
        let foregroundLuminance = relativeLuminance(of: resolvedForeground)
        let foregroundOpacity = Double(resolvedForeground.opacity)
        let compositedForegroundLuminance =
            foregroundLuminance * foregroundOpacity
            + backgroundLuminance * (1 - foregroundOpacity)
        return (max(compositedForegroundLuminance, backgroundLuminance) + 0.05)
            / (min(compositedForegroundLuminance, backgroundLuminance) + 0.05)
    }

    private static func relativeLuminance(of color: Color.Resolved) -> Double {
        0.2126 * Double(color.linearRed)
            + 0.7152 * Double(color.linearGreen)
            + 0.0722 * Double(color.linearBlue)
    }
}
