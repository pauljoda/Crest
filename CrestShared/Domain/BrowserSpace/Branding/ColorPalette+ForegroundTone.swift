import Foundation

/// The text tone a palette reads best under, measured with APCA, the
/// perceptual contrast method WCAG 3 takes up: each color as the sidebar
/// draws it, at the look's strength over the window's own background and
/// beneath the readability fade, and the tone whose weakest contrast across
/// the palette is the strongest.
extension ColorPalette {
    // MARK: - Static Variables

    /// The window's own background under each appearance, as a gray level:
    /// about the system's window color, dark and light.
    private static let darkWindowLevel = 0.12
    private static let lightWindowLevel = 0.93

    /// The screen luminance of white text and of dark text.
    private static let lightTextLuminance = screenLuminance(red: 1, green: 1, blue: 1)
    private static let darkTextLuminance = screenLuminance(red: 0, green: 0, blue: 0)

    // MARK: - Actions - Contrast

    /// The tone that reads best over this palette drawn at `strength` over a
    /// window whose own text reads `system`, under a readability fade of
    /// `readabilityFade`.
    func foregroundTone(
        strength: Double,
        readabilityFade: Double,
        system: BrowserSpaceForegroundTone
    ) -> BrowserSpaceForegroundTone {
        let window = system == .light ? Self.darkWindowLevel : Self.lightWindowLevel
        let overlay = Swift.min(readabilityFade * 0.55, 0.7)
        let backgrounds = map { color in
            Self.screenLuminance(
                red: Self.rendered(color.red, over: window, strength: strength, overlay: overlay),
                green: Self.rendered(color.green, over: window, strength: strength, overlay: overlay),
                blue: Self.rendered(color.blue, over: window, strength: strength, overlay: overlay))
        }
        let light = backgrounds.map { Self.lightnessContrast(text: Self.lightTextLuminance, over: $0) }.min() ?? 0
        let dark = backgrounds.map { Self.lightnessContrast(text: Self.darkTextLuminance, over: $0) }.min() ?? 0
        return light >= dark ? .light : .dark
    }

    /// A color channel as the sidebar draws it: at `strength` over the
    /// window's `base`, then darkened by the readability fade's `overlay`.
    private static func rendered(_ channel: Double, over base: Double, strength: Double, overlay: Double) -> Double {
        (channel * strength + base * (1 - strength)) * (1 - overlay)
    }

    /// APCA's screen luminance of a color, with its soft clamp near black.
    private static func screenLuminance(red: Double, green: Double, blue: Double) -> Double {
        let luminance = 0.2126729 * pow(red, 2.4) + 0.7151522 * pow(green, 2.4) + 0.0721750 * pow(blue, 2.4)
        return luminance < 0.022 ? luminance + pow(0.022 - luminance, 1.414) : luminance
    }

    /// APCA's lightness contrast of text of luminance `text` over a
    /// background of `background`, as a magnitude from 0 for none to about
    /// 106, whichever way round the two are.
    private static func lightnessContrast(text: Double, over background: Double) -> Double {
        guard abs(background - text) >= 0.0005 else { return 0 }
        if background > text {
            let contrast = (pow(background, 0.56) - pow(text, 0.57)) * 1.14
            return contrast < 0.1 ? 0 : (contrast - 0.027) * 100
        }
        let contrast = (pow(background, 0.65) - pow(text, 0.62)) * 1.14
        return contrast > -0.1 ? 0 : -(contrast + 0.027) * 100
    }
}
