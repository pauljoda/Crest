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

    static let presets: [BrandColor] = [
        .ink, .indigo, .ocean, .sky, .teal, .sage, .gold, .ember, .rose, .sand,
    ]

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
