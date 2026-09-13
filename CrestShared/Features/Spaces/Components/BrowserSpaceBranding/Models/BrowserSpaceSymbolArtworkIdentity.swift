import SwiftUI

struct BrowserSpaceSymbolArtworkIdentity: Equatable, Sendable {
    private enum Artwork: Equatable, Sendable {
        case crest(BrowserSpaceCrest, colors: [BrowserSpaceBrandColor])
        case symbol(color: BrowserSpaceBrandColor)
        case emoji
    }

    private let artwork: Artwork
    let symbol: String
    let accessPolicy: BrowserSpaceAccessPolicy
    let size: CGFloat
    let lockSize: CGFloat
    let colorScheme: ColorScheme
    let displayScale: CGFloat

    init(
        branding: BrowserSpaceBranding,
        symbol: String,
        accessPolicy: BrowserSpaceAccessPolicy,
        size: CGFloat,
        lockSize: CGFloat,
        colorScheme: ColorScheme,
        displayScale: CGFloat
    ) {
        if branding.iconStyle == .layeredCrest {
            var crest = branding.crest
            crest.startingPresetID = nil
            artwork = .crest(crest, colors: crest.layerColors(spaceColors: branding.colors))
        } else if BrowserIconSymbol.emoji(from: symbol) != nil {
            artwork = .emoji
        } else {
            artwork = .symbol(color: branding.resolvedSymbolColor)
        }
        self.symbol = symbol
        self.accessPolicy = accessPolicy
        self.size = size
        self.lockSize = lockSize
        self.colorScheme = colorScheme
        self.displayScale = displayScale
    }
}
