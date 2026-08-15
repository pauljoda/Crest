import Foundation

/// The palettes Crest offers as starting points for a Space.
///
/// Each one is a field/primary/charge triple in the order
/// `BrowserSpaceBrandColorRole` reads them. A palette is a template, not a
/// reference: choosing one copies its colors into the Space, so a Space keeps
/// rendering whatever it was given even after this list changes.
enum BrowserSpaceHousePalette: String, CaseIterable, Equatable, Sendable {
    case winter
    case lion
    case storm
    case dragon
    case meadow
    case iron
    case river
    case sun
    case vigil

    /// The English design-token name. It is also the user-facing label, so every
    /// name here needs a matching string-catalog entry.
    var name: String {
        switch self {
        case .winter: "Winter"
        case .lion: "Lion"
        case .storm: "Storm"
        case .dragon: "Dragon"
        case .meadow: "Meadow"
        case .iron: "Iron"
        case .river: "River"
        case .sun: "Sun"
        case .vigil: "Vigil"
        }
    }

    var colors: [BrowserSpaceBrandColor] {
        switch self {
        // Cool neutrals: one blue-grey hue family, chroma held low so the ice
        // charge reads as light rather than as a second color.
        case .winter: [.winterSlate, .winterSteel, .winterIce]
        // Crimson field with a gold charge — the classic tincture-and-metal
        // pairing, with the crimson hue held blue-side of red so the warm gold
        // sits opposite it instead of blending into it.
        case .lion: [.lionOxblood, .lionCrimson, .lionGold]
        // Violet-black night under a dimmed brass. The brass is the same hue
        // family as Lion's gold but a value and a chroma step down, so the two
        // never read as the same palette.
        case .storm: [.stormMidnight, .stormGunmetal, .stormBrass]
        // Warm black and blood. No metal at all: the palette is a single red
        // hue ramp, which is what separates it from Lion.
        case .dragon: [.dragonChar, .dragonBlood, .dragonScarlet]
        // Forest field with a wheat charge — split complements, with the wheat
        // pulled toward yellow-green so it belongs to the field.
        case .meadow: [.meadowForest, .meadowMoss, .meadowWheat]
        // Sea-iron black and a patina brass that is nearly neutral. The quietest
        // palette that still carries a metal.
        case .iron: [.ironBlack, .ironPewter, .ironPatina]
        // Navy field with a rust charge: near-complementary, both muted so the
        // pairing reads weathered rather than primary.
        case .river: [.riverNavy, .riverLapis, .riverRust]
        // A single warm ramp from burnt umber to dune, analogous rather than
        // contrasting, which keeps the brightest palette from shouting.
        case .sun: [.sunUmber, .sunTerracotta, .sunDune]
        // Layered neutral blacks. The restrained option: chroma near zero at
        // every step.
        case .vigil: [.vigilOnyx, .vigilCharcoal, .vigilAsh]
        }
    }
}
