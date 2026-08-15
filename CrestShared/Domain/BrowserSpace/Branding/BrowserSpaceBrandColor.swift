import Foundation

struct BrowserSpaceBrandColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    static let ink = BrowserSpaceBrandColor(red: 0.08, green: 0.15, blue: 0.23)
    static let indigo = BrowserSpaceBrandColor(red: 0.29, green: 0.25, blue: 0.58)
    static let ocean = BrowserSpaceBrandColor(red: 0.22, green: 0.42, blue: 0.64)
    static let sky = BrowserSpaceBrandColor(red: 0.35, green: 0.66, blue: 0.84)
    static let teal = BrowserSpaceBrandColor(red: 0.12, green: 0.49, blue: 0.52)
    static let sage = BrowserSpaceBrandColor(red: 0.39, green: 0.56, blue: 0.42)
    static let gold = BrowserSpaceBrandColor(red: 0.88, green: 0.67, blue: 0.25)
    static let ember = BrowserSpaceBrandColor(red: 0.85, green: 0.27, blue: 0.20)
    static let rose = BrowserSpaceBrandColor(red: 0.72, green: 0.25, blue: 0.42)
    static let sand = BrowserSpaceBrandColor(red: 0.82, green: 0.72, blue: 0.56)
    static let folderDefault = BrowserSpaceBrandColor(
        red: 0.43,
        green: 0.48,
        blue: 0.54
    )
    static let privateBrowsingPurple = BrowserSpaceBrandColor(
        red: 0.58,
        green: 0.30,
        blue: 0.76
    )

    static let presets: [BrowserSpaceBrandColor] = [
        .ink, .indigo, .ocean, .sky, .teal, .sage, .gold, .ember, .rose, .sand
    ]

    // MARK: - House palette tinctures
    //
    // Crest's shipped palettes are built like arms: a deep field, one related
    // tincture a value step above it, and a single luminous charge. Fields and
    // primaries stay below the flip point that `BrowserSpaceForegroundPolicy`
    // uses, so a whole palette resolves to one light foreground and sidebar text
    // never changes tone across the banner.

    static let winterSlate = BrowserSpaceBrandColor(red: 0.118, green: 0.157, blue: 0.200)
    static let winterSteel = BrowserSpaceBrandColor(red: 0.243, green: 0.306, blue: 0.369)
    static let winterIce = BrowserSpaceBrandColor(red: 0.525, green: 0.678, blue: 0.769)

    static let lionOxblood = BrowserSpaceBrandColor(red: 0.235, green: 0.055, blue: 0.102)
    static let lionCrimson = BrowserSpaceBrandColor(red: 0.447, green: 0.125, blue: 0.188)
    static let lionGold = BrowserSpaceBrandColor(red: 0.788, green: 0.635, blue: 0.329)

    static let stormMidnight = BrowserSpaceBrandColor(red: 0.082, green: 0.094, blue: 0.141)
    static let stormGunmetal = BrowserSpaceBrandColor(red: 0.192, green: 0.220, blue: 0.282)
    static let stormBrass = BrowserSpaceBrandColor(red: 0.690, green: 0.561, blue: 0.290)

    static let dragonChar = BrowserSpaceBrandColor(red: 0.102, green: 0.063, blue: 0.051)
    static let dragonBlood = BrowserSpaceBrandColor(red: 0.478, green: 0.118, blue: 0.071)
    static let dragonScarlet = BrowserSpaceBrandColor(red: 0.745, green: 0.267, blue: 0.220)

    static let meadowForest = BrowserSpaceBrandColor(red: 0.082, green: 0.137, blue: 0.094)
    static let meadowMoss = BrowserSpaceBrandColor(red: 0.204, green: 0.341, blue: 0.220)
    static let meadowWheat = BrowserSpaceBrandColor(red: 0.737, green: 0.655, blue: 0.400)

    static let ironBlack = BrowserSpaceBrandColor(red: 0.055, green: 0.102, blue: 0.110)
    static let ironPewter = BrowserSpaceBrandColor(red: 0.173, green: 0.227, blue: 0.235)
    static let ironPatina = BrowserSpaceBrandColor(red: 0.612, green: 0.592, blue: 0.506)

    static let riverNavy = BrowserSpaceBrandColor(red: 0.059, green: 0.118, blue: 0.180)
    static let riverLapis = BrowserSpaceBrandColor(red: 0.133, green: 0.282, blue: 0.424)
    static let riverRust = BrowserSpaceBrandColor(red: 0.659, green: 0.361, blue: 0.255)

    static let sunUmber = BrowserSpaceBrandColor(red: 0.208, green: 0.086, blue: 0.043)
    static let sunTerracotta = BrowserSpaceBrandColor(red: 0.545, green: 0.239, blue: 0.106)
    static let sunDune = BrowserSpaceBrandColor(red: 0.816, green: 0.620, blue: 0.396)

    static let vigilOnyx = BrowserSpaceBrandColor(red: 0.063, green: 0.067, blue: 0.071)
    static let vigilCharcoal = BrowserSpaceBrandColor(red: 0.153, green: 0.165, blue: 0.180)
    static let vigilAsh = BrowserSpaceBrandColor(red: 0.482, green: 0.514, blue: 0.549)

    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
        case alpha
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let legacyName = try? container.decode(String.self),
           let legacy = Self.legacy(named: legacyName) {
            self = legacy
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue),
            alpha: try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(alpha, forKey: .alpha)
    }

    private static func legacy(named name: String) -> BrowserSpaceBrandColor? {
        switch name {
        case "ink": .ink
        case "indigo": .indigo
        case "ocean": .ocean
        case "sky": .sky
        case "teal": .teal
        case "sage": .sage
        case "gold": .gold
        case "ember": .ember
        case "rose": .rose
        case "sand": .sand
        default: nil
        }
    }
}
