import Foundation

enum BrowserSpaceCrestChargeLayout: String, Codable, CaseIterable, Equatable, Sendable {
    case single
    case paired
    case trio
    case quad
    case ring

    var introducedInRenderingVersion: Int {
        switch self {
        case .quad, .ring: BrowserSpaceBranding.crestStudioRenderingVersion
        default: BrowserSpaceBranding.baselineRenderingVersion
        }
    }
}

enum BrowserSpaceCrestBackplate: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case circle
    case shield
    case frenchShield
    case diamond
    case seal
    case hexagon
    case octagon
    case roundedSquare
    case oval
    case banner
    case badge

    var introducedInRenderingVersion: Int {
        switch self {
        case .octagon, .roundedSquare: BrowserSpaceBranding.customizationRenderingVersion
        case .frenchShield, .oval, .banner, .badge: BrowserSpaceBranding.crestStudioRenderingVersion
        default: BrowserSpaceBranding.baselineRenderingVersion
        }
    }
}

enum BrowserSpaceCrestFieldDivision: String, Codable, CaseIterable, Equatable, Sendable {
    case plain
    case perPale
    case perFess
    case perBend
    case perChevron
    case quarterly
    case perSaltire
    case gyronny
    case barry
    case paly
    case checky

    var introducedInRenderingVersion: Int {
        switch self {
        case .perSaltire, .gyronny, .barry, .paly, .checky: BrowserSpaceBranding.crestStudioRenderingVersion
        default: BrowserSpaceBranding.baselineRenderingVersion
        }
    }

    /// Whether the division repeats, and so reads ``BrowserSpaceCrest/divisionCount``.
    var isCounted: Bool {
        switch self {
        case .gyronny, .barry, .paly, .checky: true
        default: false
        }
    }
}

enum BrowserSpaceCrestTrim: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case shield
    case line
    case doubleLine
    case laurel
    case sunburst
    case doubleRing
    case seal
    case beaded

    var introducedInRenderingVersion: Int {
        switch self {
        case .line, .doubleLine, .beaded: BrowserSpaceBranding.crestStudioRenderingVersion
        default: BrowserSpaceBranding.baselineRenderingVersion
        }
    }

    /// Whether the trim is made of repeated elements, and so reads
    /// ``BrowserSpaceCrest/trimDetail``.
    var isCounted: Bool {
        switch self {
        case .sunburst, .beaded: true
        default: false
        }
    }
}

enum BrowserSpaceCrestOrdinary: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case pale
    case fess
    case bend
    case chevron
    case cross
    case saltire
    case chief
    case bordure
    case pall
    case pile
    case canton
    case roundel

    var introducedInRenderingVersion: Int {
        switch self {
        case .pall, .pile, .canton, .roundel: BrowserSpaceBranding.crestStudioRenderingVersion
        default: BrowserSpaceBranding.baselineRenderingVersion
        }
    }
}

/// How the field's surface is lit.
enum BrowserSpaceCrestFinish: String, Codable, CaseIterable, Equatable, Sendable {
    case flat
    case sheen
    case embossed
}

/// How far the crest stands off whatever it sits on.
enum BrowserSpaceCrestDepth: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case soft
    case lifted
}

enum BrowserSpaceCrestChargeWeight: String, Codable, CaseIterable, Equatable, Sendable {
    case light
    case regular
    case bold
}

enum BrowserSpaceCrestMonogramStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case serif
    case sans
}

/// What a crest bears: a figure from the heraldic set, any system symbol, an
/// emoji, or a monogram of up to two letters.
///
/// The heraldic case keeps the old `symbol` field's spelling on disk, so a crest
/// that never chose anything else round-trips exactly as it always has.
enum BrowserSpaceCrestCharge: Equatable, Sendable, Hashable {
    case heraldic(BrowserSpaceCrestSymbol)
    case system(String)
    case emoji(String)
    case monogram(String, BrowserSpaceCrestMonogramStyle)
    case none

    static let monogramMaximumLength = 2

    var isHeraldic: Bool {
        if case .heraldic = self { return true }
        return false
    }

    /// Trims a monogram to its allowed length and drops empty custom charges.
    var normalized: BrowserSpaceCrestCharge {
        switch self {
        case .heraldic, .none:
            return self
        case .system(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? BrowserSpaceCrestCharge.none : .system(trimmed)
        case .emoji(let text):
            return text.isEmpty ? BrowserSpaceCrestCharge.none : .emoji(String(text.prefix(1)))
        case .monogram(let letters, let style):
            let trimmed = String(
                letters.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(Self.monogramMaximumLength))
            return trimmed.isEmpty ? BrowserSpaceCrestCharge.none : .monogram(trimmed.uppercased(), style)
        }
    }
}

extension BrowserSpaceCrestCharge: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value, style }
    /// `empty` keeps the on-disk spelling "none" without colliding with `Optional.none`.
    private enum Kind: String, Codable {
        case heraldic, system, emoji, monogram
        case empty = "none"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = container.decodeTolerantly(.kind, default: Kind.empty)
        let value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        switch kind {
        case .heraldic:
            self = .heraldic(BrowserSpaceCrestSymbol(rawValue: value) ?? .fallback)
        case .system:
            self = .system(value)
        case .emoji:
            self = .emoji(value)
        case .monogram:
            self = .monogram(value, container.decodeTolerantly(.style, default: .serif))
        case .empty:
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heraldic(let symbol):
            try container.encode(Kind.heraldic, forKey: .kind)
            try container.encode(symbol.rawValue, forKey: .value)
        case .system(let name):
            try container.encode(Kind.system, forKey: .kind)
            try container.encode(name, forKey: .value)
        case .emoji(let text):
            try container.encode(Kind.emoji, forKey: .kind)
            try container.encode(text, forKey: .value)
        case .monogram(let letters, let style):
            try container.encode(Kind.monogram, forKey: .kind)
            try container.encode(letters, forKey: .value)
            try container.encode(style, forKey: .style)
        case .none:
            try container.encode(Kind.empty, forKey: .kind)
        }
    }
}

/// The charges a crest can bear.
///
/// Declaration order is gallery order: beasts, sky and weather, land and
/// growing things, then works of hand. Raw values are the on-disk and CloudKit
/// spelling, so cases may be reordered but not renamed.
enum BrowserSpaceCrestSymbol: String, Codable, CaseIterable, Equatable, Sendable {
    static let fallback = BrowserSpaceCrestSymbol.mountain

    /// Oak remains decodable but is not offered because it renders identically
    /// to leaf.
    static let selectable: [BrowserSpaceCrestSymbol] = allCases.filter { $0 != .oak }

    // Beasts
    case dragon
    case direwolf
    case lion
    case stag
    case raven
    case griffin
    case eagle
    case bear
    case boar
    case fox
    case horse
    case unicorn
    case wyvern
    case hydra
    case serpent
    case kraken
    case seahorse
    case scorpion
    case bat
    case falcon
    case rose
    case lily
    case pine
    case willow
    case swords
    case axes
    case sword
    case trident
    case anchor
    case castle
    case scales
    case dragonHead
    case hound
    case paw
    case hare
    case bird
    case fish
    case bee
    case shell

    // Sky and weather
    case sun
    case risingSun
    case crescent
    case star
    case sparkles
    case lightning
    case flame
    case snowflake
    case drop

    // Land and growing things
    case mountain
    case tree
    case oak
    case leaf
    case fern
    case flower
    case waves

    // Works of hand
    case tower
    case book
    case key
    case hammer
    case compass
    case sailboat
    case crown
    case horn
    case crossedBanners

    /// The first rendering vocabulary that contains this charge.
    var introducedInRenderingVersion: Int {
        switch self {
        case .dragon, .direwolf, .lion, .stag, .raven, .griffin, .eagle, .bear, .boar, .fox, .horse, .unicorn, .wyvern,
            .hydra, .serpent, .kraken, .seahorse, .scorpion, .bat, .falcon, .rose, .lily, .pine, .willow, .swords,
            .axes, .sword, .trident, .anchor, .castle, .scales, .dragonHead:
            BrowserSpaceBranding.crestStudioRenderingVersion
        case .paw, .hound, .crown, .risingSun, .crossedBanners,
            .flower, .drop, .snowflake, .horn:
            BrowserSpaceBranding.expandedChargeRenderingVersion
        default:
            BrowserSpaceBranding.baselineRenderingVersion
        }
    }
}
