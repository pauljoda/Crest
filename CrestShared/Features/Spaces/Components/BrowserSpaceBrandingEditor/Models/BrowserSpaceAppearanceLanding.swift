import Foundation

/// Appearance values stay independent of the editor's navigation. Only the
/// durable customization intent is stored with the Space.
enum BrowserSpaceAppearanceLanding {
    static func page(for branding: BrowserSpaceBranding) -> BrowserSpaceAppearancePage {
        if branding.iconStyle == .simpleSymbol { return .icon }
        if let custom = branding.hasCustomAppearance { return custom ? .customize : .presets }
        var appearance = branding.normalized()
        appearance.hasCustomAppearance = nil
        let matchesTemplate = BrowserSpaceHousePalette.allCases.contains { palette in
            var template = BrowserSpaceBranding.house(palette, symbol: "")
            template.hasCustomAppearance = nil
            return appearance == template
        }
        return matchesTemplate ? .presets : .customize
    }

    static var customStart: BrowserSpaceBranding {
        BrowserSpaceBranding(
            colors: [.winterSlate, .winterSteel, .winterIce],
            bannerPattern: .solid, readabilityFade: BrowserSpaceBranding.initialReadabilityFade,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(backplate: .shield, trim: .shield, symbol: .mountain),
            hasCustomAppearance: true)
    }
}
