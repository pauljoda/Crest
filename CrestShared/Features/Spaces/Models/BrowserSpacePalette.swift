import SwiftUI

/// A palette a Space can take in one tap: a Background, a gradient of colors
/// at one lightness turned a little round the wheel, and an Accent set well
/// off it, so the crest and highlights read. Crest's own look comes first,
/// then three families: light pastels, clear brights and deep tones. Taking
/// one keeps the Space's crest, which then wears the Space's colors.
struct BrowserSpacePalette: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    /// Crest's own look, the colors of the Crest house: ink washing into sky
    /// toward the foot, with a butter Accent.
    static let crest = BrowserSpacePalette(
        name: "crest", title: "Crest",
        background: [Tincture.crestInk.color, Tincture.crestDusk.color, Tincture.crestSky.color],
        accent: [Tincture.crestButter.color], degrees: 75)
    /// A light pastel blossom.
    static let blossom = BrowserSpacePalette(
        name: "blossom", title: "Blossom",
        background: [
            BrandColor(red: 0.997, green: 0.814, blue: 0.864), BrandColor(red: 1.000, green: 0.846, blue: 0.778),
        ],
        accent: [BrandColor(red: 0.779, green: 0.382, blue: 0.455)])
    /// A light pastel lagoon.
    static let lagoon = BrowserSpacePalette(
        name: "lagoon", title: "Lagoon",
        background: [
            BrandColor(red: 0.752, green: 0.929, blue: 0.876), BrandColor(red: 0.730, green: 0.904, blue: 0.962),
        ],
        accent: [BrandColor(red: 0.000, green: 0.537, blue: 0.628)])
    /// A light pastel lilac.
    static let lilac = BrowserSpacePalette(
        name: "lilac", title: "Lilac",
        background: [
            BrandColor(red: 0.876, green: 0.831, blue: 0.971), BrandColor(red: 0.799, green: 0.876, blue: 1.000),
        ],
        accent: [BrandColor(red: 0.504, green: 0.409, blue: 0.747)])
    /// A light pastel linen.
    static let linen = BrowserSpacePalette(
        name: "linen", title: "Linen",
        background: [
            BrandColor(red: 0.965, green: 0.899, blue: 0.811), BrandColor(red: 0.991, green: 0.866, blue: 0.812),
        ],
        accent: [BrandColor(red: 0.749, green: 0.433, blue: 0.244)], texture: 0.5)
    /// A clear, bright sunset.
    static let sunset = BrowserSpacePalette(
        name: "sunset", title: "Sunset",
        background: [
            BrandColor(red: 0.963, green: 0.533, blue: 0.425), BrandColor(red: 0.953, green: 0.682, blue: 0.346),
        ],
        accent: [BrandColor(red: 1.000, green: 0.970, blue: 0.922)], texture: 0.2)
    /// A clear, bright ocean.
    static let ocean = BrowserSpacePalette(
        name: "ocean", title: "Ocean",
        background: [
            BrandColor(red: 0.207, green: 0.609, blue: 0.852), BrandColor(red: 0.211, green: 0.729, blue: 0.729),
        ],
        accent: [BrandColor(red: 0.874, green: 0.987, blue: 0.992)])
    /// A clear, bright orchid.
    static let orchid = BrowserSpacePalette(
        name: "orchid", title: "Orchid",
        background: [
            BrandColor(red: 0.648, green: 0.390, blue: 0.821), BrandColor(red: 0.873, green: 0.415, blue: 0.651),
        ],
        accent: [BrandColor(red: 1.000, green: 0.940, blue: 0.992)])
    /// A clear, bright citrus.
    static let citrus = BrowserSpacePalette(
        name: "citrus", title: "Citrus",
        background: [
            BrandColor(red: 0.707, green: 0.860, blue: 0.406), BrandColor(red: 0.930, green: 0.853, blue: 0.387),
        ],
        accent: [BrandColor(red: 0.205, green: 0.386, blue: 0.164)])
    /// A deep midnight.
    static let midnight = BrowserSpacePalette(
        name: "midnight", title: "Midnight",
        background: [
            BrandColor(red: 0.092, green: 0.152, blue: 0.295), BrandColor(red: 0.211, green: 0.169, blue: 0.375),
        ],
        accent: [BrandColor(red: 0.705, green: 0.834, blue: 0.971)], texture: 0.2)
    /// A deep forest.
    static let forest = BrowserSpacePalette(
        name: "forest", title: "Forest",
        background: [
            BrandColor(red: 0.038, green: 0.215, blue: 0.138), BrandColor(red: 0.000, green: 0.268, blue: 0.257),
        ],
        accent: [BrandColor(red: 0.727, green: 0.866, blue: 0.696)], texture: 0.25)
    /// A deep ember.
    static let ember = BrowserSpacePalette(
        name: "ember", title: "Ember",
        background: [
            BrandColor(red: 0.321, green: 0.083, blue: 0.102), BrandColor(red: 0.434, green: 0.104, blue: 0.050),
        ],
        accent: [BrandColor(red: 0.954, green: 0.786, blue: 0.595)], texture: 0.35)
    /// A deep plum.
    static let plum = BrowserSpacePalette(
        name: "plum", title: "Plum",
        background: [
            BrandColor(red: 0.253, green: 0.102, blue: 0.243), BrandColor(red: 0.249, green: 0.168, blue: 0.372),
        ],
        accent: [BrandColor(red: 0.923, green: 0.801, blue: 0.908)])

    static let all: [BrowserSpacePalette] = [
        crest, blossom, lagoon, lilac, linen, sunset, ocean, orchid, citrus, midnight, forest, ember, plum,
    ]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    /// The Background's colors, running top to bottom.
    let background: [BrandColor]
    /// The Accent's colors.
    let accent: [BrandColor]
    /// Where the Background runs: 0 left to right, 90 top to bottom.
    let degrees: Double
    /// How strongly grain lies over the Background, for a palette whose
    /// colors have a material, such as linen.
    let texture: Double

    var id: String { name }

    var backgroundFill: CrestColorFill { CrestColorFill(background, degrees: degrees) }
    var accentFill: CrestColorFill { CrestColorFill(accent) }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, background: [BrandColor], accent: [BrandColor],
        degrees: Double = 90, texture: Double = 0
    ) {
        self.name = name
        self.title = title
        self.background = background
        self.accent = accent
        self.degrees = degrees
        self.texture = texture
    }

    // MARK: - Functions

    /// Whether `branding` wears this palette's colors.
    func isWorn(by branding: SpaceBranding) -> Bool {
        Self.same(branding.backgroundFill.colors, background) && Self.same(branding.accentFill.colors, accent)
    }

    /// `branding` in this palette's colors and texture, keeping its crest,
    /// which wears the colors.
    func applying(to branding: SpaceBranding) -> SpaceBranding {
        var look = branding
        look.followSpaceColors()
        look.backgroundFill = backgroundFill
        look.accentFill = accentFill
        look.textureStrength = texture
        look.hasCustomAppearance = true
        return look.normalized()
    }

    private static func same(_ colors: [BrandColor], _ others: [BrandColor]) -> Bool {
        colors.count == others.count && zip(colors, others).allSatisfy { $0.matches($1) }
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSpacePalette, rhs: BrowserSpacePalette) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
