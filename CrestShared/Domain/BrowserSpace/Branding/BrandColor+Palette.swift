import Foundation

/// The named colors Crest offers and draws with.
extension BrandColor {
    // MARK: - Static Variables

    // The everyday colors, by the names code reaches for; the core declares
    // each as a tincture.
    static let ink = Tincture.ink.color
    static let indigo = Tincture.indigo.color
    static let ocean = Tincture.ocean.color
    static let sky = Tincture.sky.color
    static let teal = Tincture.teal.color
    static let sage = Tincture.sage.color
    static let gold = Tincture.gold.color
    static let ember = Tincture.ember.color
    static let rose = Tincture.rose.color
    static let sand = Tincture.sand.color
    static let folderDefault = BrandColor(red: 0.43, green: 0.48, blue: 0.54, alpha: 1)
    #if os(macOS)
        /// What an agent that gives no brand colour of its own wears.
        static let agentDefault = BrandColor(red: 0.53, green: 0.54, blue: 0.56, alpha: 1)
    #endif

    static let presets: [BrandColor] = [
        .ink, .indigo, .ocean, .sky, .teal, .sage, .gold, .ember, .rose, .sand,
    ]

    /// How bright a fully dimmed color draws, from its darkest to its
    /// brightest: a charcoal base tinted with its hue. The sidebar's layers
    /// lighten it a little, so a light gray Space shows as a neutral charcoal
    /// near #2B2B2B.
    private static let dimmedBrightness: ClosedRange<Double> = 0.08...0.12
    /// How much of a color's saturation stays once it is fully dimmed.
    private static let dimmedSaturation = 0.8
    /// How far apart a color's strongest and weakest components may be for a
    /// palette to still place it with the grays.
    private static let grayChroma = 0.1
    /// How far round the wheel a palette's hues start, so the crimsons that
    /// sit just short of red lead the reds rather than trail the purples.
    private static let paletteHueOffset = 0.1

    // MARK: - Variables

    /// The tone that reads best over this one solid color.
    var foregroundTone: BrowserSpaceForegroundTone {
        ColorPalette(colors: [self]).foregroundTone(strength: 1, readabilityFade: 0, system: .light)
    }

    // MARK: - Initializers

    /// An opaque color, each component kept within 0 through 1.
    init(red: Double, green: Double, blue: Double) {
        self.init(clampingRed: red, green: green, blue: blue, alpha: 1)
    }

    /// A color as a color picker or the system gives it, each component kept
    /// within 0 through 1.
    init(clampingRed red: Double, green: Double, blue: Double, alpha: Double) {
        self.init(red: Self.unit(red), green: Self.unit(green), blue: Self.unit(blue), alpha: Self.unit(alpha))
    }

    // MARK: - Actions - Dimming

    /// This color dimmed `amount` of the way, from 0 to 1, toward a charcoal
    /// tint of itself: the same hue, slightly less saturated, darkened toward
    /// black, so a light color turns dark and a dark one stays as dark as it is.
    func dimmed(by amount: Double) -> BrandColor {
        let highest = Swift.max(red, green, blue)
        let lowest = Swift.min(red, green, blue)
        let range = Self.dimmedBrightness
        let brightness = Swift.min(highest, range.lowerBound + (range.upperBound - range.lowerBound) * highest)
        let saturation = highest > 0 ? (highest - lowest) / highest * Self.dimmedSaturation : 0
        let spread = highest - lowest
        func channel(_ value: Double) -> Double {
            let distance = spread > 0 ? (highest - value) / spread : 0
            return value + (brightness * (1 - saturation * distance) - value) * amount
        }
        return BrandColor(clampingRed: channel(red), green: channel(green), blue: channel(blue), alpha: alpha)
    }

    // MARK: - Actions - Comparing

    /// Whether two colors look the same, allowing for rounding.
    func matches(_ other: BrandColor) -> Bool {
        abs(red - other.red) < 0.004 && abs(green - other.green) < 0.004 && abs(blue - other.blue) < 0.004
    }

    /// The named tincture this color is, if it is one.
    var tincture: Tincture? {
        Tincture.all.first { $0.color.matches(self) }
    }

    /// How light the color looks, from 0 for black to 1 for white.
    var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// Whether the color comes before `other` in a palette: the grays first,
    /// darkest first, then the hues from the crimsons round the wheel.
    func precedesInPalette(_ other: BrandColor) -> Bool {
        paletteOrder < other.paletteOrder
    }

    /// Where the color sits in a palette: whether it has a hue, then how
    /// light a gray is or how far round the wheel a hue is.
    private var paletteOrder: (Int, Double) {
        let spread = Swift.max(red, green, blue) - Swift.min(red, green, blue)
        guard spread >= Self.grayChroma else { return (0, luminance) }
        return (1, (hue(spread: spread) + Self.paletteHueOffset).truncatingRemainder(dividingBy: 1))
    }

    /// The color's hue, from 0 for red round the wheel to 1, for a color
    /// whose strongest and weakest components are `spread` apart.
    private func hue(spread: Double) -> Double {
        let highest = Swift.max(red, green, blue)
        let sector =
            highest == red
            ? (green - blue) / spread : highest == green ? (blue - red) / spread + 2 : (red - green) / spread + 4
        let turn = sector / 6
        return turn < 0 ? turn + 1 : turn
    }

    // MARK: - Actions - Components

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

extension BrandColor: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(red)
        hasher.combine(green)
        hasher.combine(blue)
        hasher.combine(alpha)
    }
}

/// A color as the device's appearance settings store it: its components,
/// opaque unless it says.
extension BrandColor: Codable {
    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
        case alpha
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            clampingRed: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue),
            alpha: try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(alpha, forKey: .alpha)
    }
}
