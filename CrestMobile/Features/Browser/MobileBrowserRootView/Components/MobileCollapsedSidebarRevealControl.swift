import SwiftUI

struct MobileCollapsedSidebarRevealControl: View {
    let showSidebar: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Color.clear
            .contentShape(.rect)
            .frame(width: MobileBrowserChromeLayout.collapsedSidebarRevealWidth)
            .frame(maxHeight: .infinity)
            .gesture(
                DragGesture(
                    minimumDistance: MobileBrowserChromeLayout
                        .collapsedSidebarGestureDistance
                )
                .onEnded { value in
                    guard
                        BrowserChromeDirectionPolicy.isLeadingEdgeReveal(
                            value.translation,
                            layoutDirection: layoutDirection
                        )
                    else {
                        return
                    }
                    showSidebar()
                }
            )
            .accessibilityRepresentation {
                Button("Show Sidebar", systemImage: "sidebar.left") {
                    showSidebar()
                }
                .accessibilityHint(
                    "You can also swipe inward from the leading edge"
                )
                .accessibilityIdentifier("show-sidebar")
            }
    }
}
