/// The order the banner forge presents its steps in.
///
/// The forge is one scrollable surface, not a paged wizard. Its steps follow
/// the order arms are composed: field, cut, mark, then crest layers.
enum BrowserSpaceForgeStep: String, CaseIterable, Identifiable, Sendable {
    case field
    case pattern
    case mark
    case shield
    case division
    case ordinary
    case charge
    case trim

    var id: String { rawValue }

    static let crestSteps: [BrowserSpaceForgeStep] = [
        .shield, .division, .ordinary, .charge, .trim,
    ]

    var accessibilityIdentifier: String { "space-forge-\(rawValue)" }

    var isCrestStep: Bool { Self.crestSteps.contains(self) }
}
