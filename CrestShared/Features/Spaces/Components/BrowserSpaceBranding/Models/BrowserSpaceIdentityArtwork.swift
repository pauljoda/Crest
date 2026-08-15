enum BrowserSpaceIdentityArtwork: Equatable {
    case crest
    case symbol(String)

    init(space: BrowserSpace) {
        self =
            space.branding.iconStyle == .layeredCrest
            ? .crest
            : .symbol(space.symbol)
    }
}
