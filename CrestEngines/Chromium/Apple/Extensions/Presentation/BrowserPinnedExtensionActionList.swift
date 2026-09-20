import SwiftUI

struct BrowserPinnedExtensionActionList: View {
    let actions: [BrowserExtensionActionPresentation]
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    var prepare: (BrowserExtensionActionPresentation) -> Void = { _ in }
    var presentMenu:
        (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) ->
            Void = { _, _ in }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(
                    spacing: BrowserPinnedExtensionStripLayoutPolicy.spacing
                ) {
                    ForEach(actions) { action in
                        BrowserPinnedExtensionActionButton(
                            action: action,
                            perform: { perform(action, $0) },
                            prepare: { prepare(action) },
                            presentMenu: { presentMenu(action, $0) }
                        )
                    }
                }
                // Size the scroll content in both axes so the buttons stay
                // centered when the viewport is laid out again.
                .frame(
                    minWidth: proxy.size.width,
                    minHeight: proxy.size.height
                )
            }
            .scrollIndicators(.hidden)
        }
    }
}
