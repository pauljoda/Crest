import SwiftUI

enum MobileRegularBrowserBackdropPolicy {
    static let rootOwnsAtmosphere = true
    static let atmosphereSafeAreaEdges: Edge.Set = .all
    static let extendsBehindTopSafeArea = atmosphereSafeAreaEdges.contains(.top)
}

enum MobileStartPageAppearancePolicy {
    static func foregroundTone(
        usesCommandPalette _: Bool
    ) -> MobileStartPageForegroundTone {
        .onBrand
    }
}

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
