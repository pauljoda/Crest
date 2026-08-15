enum MobileStartPageSearchPolicy {
    static let usesSharedCommandPalette = true
    static let focusesWhenNewTabOpens = true

    static func destination(
        isStartPage: Bool,
        presentation: MobileBrowserPresentation
    ) -> MobileStartPageSearchDestination {
        switch (isStartPage, presentation) {
        case (true, _), (false, .compact):
            .embeddedStartPage
        case (false, .regular):
            .overlay
        }
    }
}
