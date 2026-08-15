import Foundation

enum BrowserPrivateBrowsingAppearance {
    static let symbol = "eyeglasses"
    static let color = BrowserSpaceBrandColor.privateBrowsingPurple
    static let backgroundDimmingOpacity = 0.55
    static let branding = BrowserSpaceBranding(
        colors: [color],
        bannerPattern: .solid,
        bannerStrength: 1,
        readabilityFade: 1,
        iconStyle: .simpleSymbol,
        crest: BrowserSpaceCrest(
            backplate: .none,
            trim: .none,
            symbol: .key
        )
    )
}
