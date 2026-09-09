import SwiftUI

enum MobileStartPageAppearancePolicy {
    static func foregroundTone(
        usesCommandPalette _: Bool
    ) -> MobileStartPageForegroundTone {
        .onBrand
    }
}

enum MobileStartPageSearchPolicy {

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
