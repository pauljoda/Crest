import SwiftUI

/// A term in Crest's heraldic vocabulary.
///
/// Every one of these names is a design token *and* a visible gallery label, so
/// each carries an English name for the code to reason about and a catalog key
/// for the reader to see. The catalog entries are hand-kept: `titleKey` builds a
/// key from a runtime string, which the compiler cannot extract, so a term added
/// here needs its entry added to `Localizable.xcstrings` by hand.
protocol BrowserSpaceHeraldicTerm {
    var title: String { get }
}

extension BrowserSpaceHeraldicTerm {
    var titleKey: LocalizedStringKey { LocalizedStringKey(title) }
}

extension BrowserSpaceIconStyle: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .simpleSymbol: "Simple Symbol"
        case .layeredCrest: "Layered Crest"
        }
    }
}

extension BrowserSpaceBannerPattern: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .solid: "Solid"
        case .split: "Split"
        case .bands: "Bands"
        case .diagonal: "Diagonal"
        case .chevron: "Chevron"
        case .quartered: "Quartered"
        }
    }
}

extension BrowserSpaceCrestBackplate: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .none: "None"
        case .circle: "Round"
        case .shield: "Shield"
        case .diamond: "Lozenge"
        case .seal: "Seal"
        case .hexagon: "Hexagon"
        }
    }

    var systemImage: String? {
        switch self {
        case .none: nil
        case .circle: "circle.fill"
        case .shield: "shield.fill"
        case .diamond: "diamond.fill"
        case .seal: "seal.fill"
        case .hexagon: "hexagon.fill"
        }
    }

    var outlineSystemImage: String? {
        switch self {
        case .none: nil
        case .circle: "circle"
        case .shield: "shield"
        case .diamond: "diamond"
        case .seal: "seal"
        case .hexagon: "hexagon"
        }
    }
}

extension BrowserSpaceCrestChargeLayout: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .single: "One"
        case .paired: "Two"
        case .trio: "Three"
        }
    }
}

extension BrowserSpaceCrestFieldDivision: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        // Kept to one word: these are gallery card captions under a 46pt crest,
        // and the card already shows what the division does.
        case .plain: "Plain"
        case .perPale: "Vertical"
        case .perFess: "Horizontal"
        case .perBend: "Diagonal"
        case .perChevron: "Chevron"
        case .quarterly: "Quartered"
        }
    }
}

extension BrowserSpaceCrestOrdinary: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .none: "None"
        case .pale: "Pale"
        case .fess: "Fess"
        case .bend: "Bend"
        case .chevron: "Chevron"
        case .cross: "Cross"
        case .saltire: "Saltire"
        case .chief: "Chief"
        case .bordure: "Bordure"
        }
    }
}

extension BrowserSpaceCrestTrim: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .none: "None"
        case .shield: "Shield"
        case .laurel: "Laurel"
        case .sunburst: "Sunburst"
        case .doubleRing: "Double Ring"
        case .seal: "Seal"
        }
    }
}

extension BrowserSpaceCrestSymbol: BrowserSpaceHeraldicTerm {
    var title: String {
        switch self {
        case .hound: "Hound"
        case .paw: "Paw"
        case .hare: "Hare"
        case .bird: "Bird"
        case .fish: "Fish"
        // Named for the glyph that actually draws, not the glyph Crest wished for.
        case .bee: "Beetle"
        case .shell: "Shell"
        case .sun: "Sun"
        case .risingSun: "Rising Sun"
        case .crescent: "Crescent"
        case .star: "Star"
        case .sparkles: "Sparkles"
        case .lightning: "Lightning"
        case .flame: "Flame"
        case .snowflake: "Snowflake"
        case .drop: "Drop"
        case .mountain: "Mountain"
        case .tree: "Tree"
        case .oak: "Oak"
        case .leaf: "Leaf"
        case .fern: "Frond"
        case .flower: "Flower"
        case .waves: "Waves"
        case .tower: "Tower"
        case .book: "Book"
        case .key: "Key"
        case .hammer: "Hammer"
        case .compass: "Compass"
        case .sailboat: "Sailboat"
        case .crown: "Crown"
        case .horn: "Horn"
        case .crossedBanners: "Banners"
        }
    }

    /// Every charge is an SF Symbol, chosen for a silhouette that survives being
    /// drawn at a third of a 24pt sidebar icon. Charges Crest wanted but could
    /// not source a worthy symbol for are absent rather than approximated.
    var systemImage: String {
        switch self {
        case .hound: "dog.fill"
        case .paw: "pawprint.fill"
        case .hare: "hare.fill"
        case .bird: "bird.fill"
        case .fish: "fish.fill"
        case .bee: "ladybug.fill"
        case .shell: "fossil.shell.fill"
        case .sun: "sun.max.fill"
        case .risingSun: "sun.horizon.fill"
        case .crescent: "moon.fill"
        case .star: "star.fill"
        case .sparkles: "sparkles"
        case .lightning: "bolt.fill"
        case .flame: "flame.fill"
        case .snowflake: "snowflake"
        case .drop: "drop.fill"
        case .mountain: "mountain.2.fill"
        case .tree: "tree.fill"
        // `oak` has no symbol of its own and draws `leaf`'s; it is kept out of the
        // gallery rather than shown twice. `fern` takes the laurel frond.
        case .oak: "leaf.fill"
        case .leaf: "leaf.fill"
        case .fern: "laurel.leading"
        case .flower: "camera.macro"
        case .waves: "water.waves"
        case .tower: "building.columns.fill"
        case .book: "book.closed.fill"
        case .key: "key.fill"
        case .hammer: "hammer.fill"
        case .compass: "location.north.circle.fill"
        case .sailboat: "sailboat.fill"
        case .crown: "crown.fill"
        case .horn: "horn.fill"
        case .crossedBanners: "flag.2.crossed.fill"
        }
    }
}
