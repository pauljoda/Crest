import Foundation

/// The looks setup's welcome idles through, a house or a palette at a time,
/// light and dark among them.
@MainActor
struct BrowserSetupIdleLooks {
    // MARK: - Static Variables

    static let all: [BrowserSetupIdleLooks] = [
        palette(.blossom), house(.dragon), palette(.lagoon), house(.river), palette(.sunset), palette(.midnight),
        palette(.citrus), house(.meadow), palette(.orchid), house(.lion),
    ]

    // MARK: - Variables

    /// The look this one dresses a Space's own look in.
    private let dress: (SpaceBranding) -> SpaceBranding

    // MARK: - Initializers

    private init(dress: @escaping (SpaceBranding) -> SpaceBranding) {
        self.dress = dress
    }

    private static func palette(_ palette: BrowserSpacePalette) -> BrowserSetupIdleLooks {
        BrowserSetupIdleLooks { palette.applying(to: $0) }
    }

    private static func house(_ house: SpaceHouse) -> BrowserSetupIdleLooks {
        BrowserSetupIdleLooks { house.applying(to: $0) }
    }

    // MARK: - Functions

    /// `base`, a Space's own look, in this one.
    func wearing(on base: SpaceBranding) -> SpaceBranding {
        dress(base)
    }
}
