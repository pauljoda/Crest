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
    /// not source a worthy symbol for — a lion, a dragon, a stag, a kraken, a
    /// bear, crossed swords — are absent rather than approximated.
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
        // gallery rather than shown twice. `fern` takes the laurel frond, which
        // is the one genuinely fern-shaped glyph in the family.
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
