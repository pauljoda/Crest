import CoreGraphics
import Foundation

/// A color as the color wheel reads it: its hue, the angle round the wheel
/// from red at the top clockwise; its vibrancy, how far out from the gray
/// center it sits, vivid at the rim; and its lightness, which the wheel is
/// drawn at and Brightness sets. These are its HSL hue, saturation and
/// lightness, so a color read here comes back exactly.
struct CrestColorWheelPoint: Equatable {
    // MARK: - Static Variables

    /// How near black or white a set lightness comes, which looks black or
    /// white but keeps the color's hue and vibrancy.
    static let edgeLightness = 0.004

    // MARK: - Variables

    /// The hue, from 0 to 1.
    let hue: Double
    /// How vivid the color is, from 0 for gray at the center to 1 at the rim.
    let vibrancy: Double
    /// The lightness, from 0 for black to 1 for white.
    let lightness: Double

    /// Where the color sits on a wheel of radius 1 centered on the origin,
    /// with y running down.
    var position: CGPoint {
        let angle = hue * 2 * .pi
        return CGPoint(x: sin(angle) * vibrancy, y: -cos(angle) * vibrancy)
    }

    /// The color itself.
    var color: BrandColor {
        let chroma = (1 - abs(2 * lightness - 1)) * vibrancy
        let sector = hue * 6
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness - chroma / 2
        let (red, green, blue): (Double, Double, Double) =
            switch Int(sector) % 6 {
            case 0: (chroma, second, 0)
            case 1: (second, chroma, 0)
            case 2: (0, chroma, second)
            case 3: (0, second, chroma)
            case 4: (second, 0, chroma)
            default: (chroma, 0, second)
            }
        return BrandColor(red: red + match, green: green + match, blue: blue + match)
    }

    // MARK: - Initializers

    init(hue: Double, vibrancy: Double, lightness: Double) {
        let turned = hue.truncatingRemainder(dividingBy: 1)
        self.hue = turned < 0 ? turned + 1 : turned
        self.vibrancy = min(max(vibrancy, 0), 1)
        self.lightness = min(max(lightness, 0), 1)
    }

    /// The color at `position` on a wheel of radius 1 centered on the
    /// origin, y running down, at `lightness`. A position past the rim
    /// takes the rim.
    init(position: CGPoint, lightness: Double) {
        let distance = hypot(position.x, position.y)
        let angle = atan2(position.x, -position.y)
        self.init(hue: angle / (2 * .pi), vibrancy: distance, lightness: lightness)
    }

    /// `color` as the wheel reads it.
    init(_ color: BrandColor) {
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        let lightness = (high + low) / 2
        let spread = high - low
        var hue = 0.0
        if spread > 0 {
            if high == color.red {
                hue = ((color.green - color.blue) / spread).truncatingRemainder(dividingBy: 6)
            } else if high == color.green {
                hue = (color.blue - color.red) / spread + 2
            } else {
                hue = (color.red - color.green) / spread + 4
            }
            hue /= 6
        }
        let room = 1 - abs(2 * lightness - 1)
        self.init(hue: hue, vibrancy: room > 0 ? spread / room : 0, lightness: lightness)
    }

    // MARK: - Functions

    /// The color at this hue and vibrancy, at `lightness`.
    func with(lightness: Double) -> CrestColorWheelPoint {
        CrestColorWheelPoint(hue: hue, vibrancy: vibrancy, lightness: lightness)
    }
}
