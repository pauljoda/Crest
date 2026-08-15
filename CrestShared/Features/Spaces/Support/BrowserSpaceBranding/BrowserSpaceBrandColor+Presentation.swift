import SwiftUI

extension BrowserSpaceBrandColor {
    private static let namedTitles: [BrowserSpaceBrandColor: String] = [
        .ink: "Ink",
        .indigo: "Indigo",
        .ocean: "Ocean",
        .sky: "Sky",
        .teal: "Teal",
        .sage: "Sage",
        .gold: "Gold",
        .ember: "Ember",
        .rose: "Rose",
        .sand: "Sand",
        .winterSlate: "Slate",
        .winterSteel: "Steel",
        .winterIce: "Ice",
        .lionOxblood: "Oxblood",
        .lionCrimson: "Crimson",
        .lionGold: "Antique Gold",
        .stormMidnight: "Midnight",
        .stormGunmetal: "Gunmetal",
        .stormBrass: "Brass",
        .dragonChar: "Char",
        .dragonBlood: "Blood",
        .dragonScarlet: "Scarlet",
        .meadowForest: "Forest",
        .meadowMoss: "Moss",
        .meadowWheat: "Wheat",
        .ironBlack: "Iron",
        .ironPewter: "Pewter",
        .ironPatina: "Patina",
        .riverNavy: "Navy",
        .riverLapis: "Lapis",
        .riverRust: "Rust",
        .sunUmber: "Umber",
        .sunTerracotta: "Terracotta",
        .sunDune: "Dune",
        .vigilOnyx: "Onyx",
        .vigilCharcoal: "Charcoal",
        .vigilAsh: "Ash",
    ]

    var title: String {
        Self.namedTitles[self] ?? "Custom"
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
