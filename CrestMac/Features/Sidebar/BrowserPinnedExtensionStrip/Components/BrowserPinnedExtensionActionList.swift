import SwiftUI

struct BrowserPinnedExtensionActionList: View {
    let actions: [BrowserExtensionActionPresentation]
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    var presentMenu:
        (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) ->
            Void = { _, _ in }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(
                    spacing: BrowserPinnedExtensionStripLayoutPolicy.spacing
                ) {
                    ForEach(actions) { action in
                        BrowserPinnedExtensionActionButton(
                            action: action,
                            perform: { perform(action, $0) },
                            presentMenu: { presentMenu(action, $0) }
                        )
                    }
                }
                .frame(minWidth: proxy.size.width)
            }
            .scrollIndicators(.hidden)
        }
    }
}
