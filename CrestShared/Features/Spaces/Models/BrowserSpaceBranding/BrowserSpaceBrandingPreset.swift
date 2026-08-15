import SwiftUI

struct BrowserSpaceBrandingPreset: Identifiable, Equatable, Sendable {
    let title: String
    let colors: [BrowserSpaceBrandColor]

    var id: String { title }

    /// The swatch label is user-facing. Every palette name has a hand-kept
    /// string-catalog entry, so the label goes through the catalog rather than
    /// rendering the design-token name verbatim.
    var titleKey: LocalizedStringKey { LocalizedStringKey(title) }

    static let curated = BrowserSpaceHousePalette.allCases.map {
        BrowserSpaceBrandingPreset(title: $0.name, colors: $0.colors)
    }

    func applying(to branding: BrowserSpaceBranding) -> BrowserSpaceBranding {
        var updated = branding
        updated.colors = colors
        return updated.normalized()
    }

    func isSelected(in branding: BrowserSpaceBranding) -> Bool {
        branding.colors == colors
    }
}
