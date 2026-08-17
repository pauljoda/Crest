import Foundation

enum BrowserSpaceCrestChargeLayout: String, Codable, CaseIterable, Equatable, Sendable {
    case single
    case paired
    case trio
}

enum BrowserSpaceCrestBackplate: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case circle
    case shield
    case diamond
    case seal
    case hexagon
}

enum BrowserSpaceCrestFieldDivision: String, Codable, CaseIterable, Equatable, Sendable {
    case plain
    case perPale
    case perFess
    case perBend
    case perChevron
    case quarterly
}

enum BrowserSpaceCrestTrim: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case shield
    case laurel
    case sunburst
    case doubleRing
    case seal
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
        case .paw, .hound, .crown, .risingSun, .crossedBanners,
            .flower, .drop, .snowflake, .horn:
            BrowserSpaceBranding.expandedChargeRenderingVersion
        default:
            BrowserSpaceBranding.baselineRenderingVersion
        }
    }
}
