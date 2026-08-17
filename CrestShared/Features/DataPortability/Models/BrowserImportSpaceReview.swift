import Foundation

struct BrowserImportSpaceReview: Codable, Equatable, Sendable, Identifiable {
    var sourceSpace: BrowserSpace
    var destination: BrowserImportDestination
    var customization: BrowserImportSpaceCustomization
    var includedTabIDs: Set<TabID>
    var duplicateTabIDs: Set<TabID>
    var placementOverrides: [TabID: TabPlacement]
    var spaceInclusionOverride: Bool?
    var passwordInclusionOverride: Bool?

    var id: SpaceID { sourceSpace.id }
    var isIncluded: Bool { spaceInclusionOverride ?? true }
    var includesPasswords: Bool {
        isIncluded && (passwordInclusionOverride ?? true)
    }

    func placement(for tab: BrowserTab) -> TabPlacement {
        placementOverrides[tab.id] ?? tab.placement
    }
}

struct BrowserImportSpaceCustomization: Codable, Equatable, Sendable {
    static let fallbackName = "Untitled Space"
    static let fallbackSymbol = "square.grid.2x2"

    var name: String
    var symbol: String
    var accent: SpaceAccent
    var branding: BrowserSpaceBranding

    init(space: BrowserSpace) {
        name = space.name
        symbol = space.symbol
        accent = space.accent
        branding = space.branding
    }

    /// The identity a Space actually takes on. Both setup routes — manual setup and
    /// a reviewed import — edit this customization through free-text fields, so the
    /// one place that hands it to a `BrowserSpace` is also the one place that
    /// decides what a blank field means.
    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.fallbackName : trimmed
    }

    var resolvedSymbol: String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.fallbackSymbol : trimmed
    }

    func apply(to space: inout BrowserSpace) {
        space.name = resolvedName
        space.symbol = resolvedSymbol
        space.accent = accent
        space.branding = branding.normalized()
    }
}
