import Foundation

enum BrowserSpaceForegroundPolicy {
    static func tone(
        for branding: BrowserSpaceBranding
    ) -> BrowserSpaceForegroundTone {
        let colors = branding.colors.isEmpty ? [.indigo] : branding.colors
        let lightContrast = minimumContrast(
            for: .light,
            colors: colors,
            branding: branding
        )
        let darkContrast = minimumContrast(
            for: .dark,
            colors: colors,
            branding: branding
        )
        return lightContrast >= darkContrast ? .light : .dark
    }

    private static func minimumContrast(
        for tone: BrowserSpaceForegroundTone,
        colors: [BrowserSpaceBrandColor],
        branding: BrowserSpaceBranding
    ) -> Double {
        let baseChannel = tone == .light ? 0.0 : 1.0
        let textLuminance = tone == .light ? 1.0 : 0.0
        let strength = branding.bannerStrength
        let readabilityOverlay = min(branding.readabilityFade * 0.55, 0.7)

        return colors.map { color in
            let red = renderedChannel(
                color.red,
                base: baseChannel,
                strength: strength,
                overlay: readabilityOverlay
            )
            let green = renderedChannel(
                color.green,
                base: baseChannel,
                strength: strength,
                overlay: readabilityOverlay
            )
            let blue = renderedChannel(
                color.blue,
                base: baseChannel,
                strength: strength,
                overlay: readabilityOverlay
            )
            let backgroundLuminance =
                0.2126 * linearComponent(red)
                + 0.7152 * linearComponent(green)
                + 0.0722 * linearComponent(blue)
            let lighter = max(textLuminance, backgroundLuminance)
            let darker = min(textLuminance, backgroundLuminance)
            return (lighter + 0.05) / (darker + 0.05)
        }
        .min() ?? 1
    }

    private static func renderedChannel(
        _ channel: Double,
        base: Double,
        strength: Double,
        overlay: Double
    ) -> Double {
        let composited = channel * strength + base * (1 - strength)
        return composited * (1 - overlay)
    }

    private static func linearComponent(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }
}
