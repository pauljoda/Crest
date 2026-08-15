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

#Preview("Empty Quick Window") {
    BrowserQuickWindowLookupStartView(
        space: BrowserQuickWindowPreviewFixture.sourceSpace
    )
    .frame(width: 480, height: 320)
}
