import Foundation

/// The charges a crest can bear.
///
/// Declaration order is gallery order, so the cases are grouped the way the
/// picker reads them — beasts, then sky and weather, then land and growing
/// things, then works of hand — rather than in the order they were added. The
/// raw value is the on-disk and on-CloudKit spelling of a charge: reordering is
/// free, renaming silently restyles every Space that chose it.
///
/// A charge added after the shipped vocabulary declares itself in
/// ``BrowserSpaceCrestSymbol/introducedInRenderingVersion``.
enum BrowserSpaceCrestSymbol: String, Codable, CaseIterable, Equatable, Sendable {
    /// The charge every unknown or unreadable charge resolves to. It has to be a
    /// shape that means nothing in particular and reads at every size.
    static let fallback = BrowserSpaceCrestSymbol.mountain

    /// The charges the gallery offers.
    ///
    /// Narrower than `allCases`, and deliberately so: `oak` has no SF Symbol of
    /// its own and draws the same leaf as `leaf`, so offering both would put two
    /// identical cards side by side under different names. It stays in the
    /// vocabulary — Spaces that already chose it keep rendering — but it is not
    /// something new arms should be built from.
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
    ///
    /// A build that predates a charge cannot draw it, so a Space wearing one
    /// announces the newer vocabulary when it encodes. See
    /// ``BrowserSpaceBranding/renderingVersion``.
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
