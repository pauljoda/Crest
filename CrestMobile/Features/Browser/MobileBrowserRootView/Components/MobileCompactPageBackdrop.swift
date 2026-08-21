import SwiftUI
import UIKit

struct MobileCompactPageBackdrop: View {
    let isStartPage: Bool
    let hasSelectedPage: Bool
    let pageThemeColor: UIColor?
    let underPageBackgroundColor: UIColor?
    let space: BrowserSpace?

    var body: some View {
        if MobileCompactPageChromePolicy.usesPageThemeBackdrop,
            !isStartPage,
            hasSelectedPage
        {
            Color(
                uiColor: pageThemeColor
                    ?? underPageBackgroundColor
                    ?? .systemBackground
            )
            .ignoresSafeArea()
        } else {
            BrowserWindowAtmosphere(space: space)
                .ignoresSafeArea()
        }
    }
}
