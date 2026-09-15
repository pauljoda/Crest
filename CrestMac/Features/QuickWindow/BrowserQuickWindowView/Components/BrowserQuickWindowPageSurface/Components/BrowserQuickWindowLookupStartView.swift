import SwiftUI

struct BrowserQuickWindowLookupStartView: View {
    let space: BrowserSpace?

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(
                "Empty Quick Window using \(space?.name ?? "Space")"
            )
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserQuickWindowLookupStartView(space: BrowserSpaceBrandingPreviewFixture.simpleSpace).frame(
            width: 540, height: 360)
    }
#endif
