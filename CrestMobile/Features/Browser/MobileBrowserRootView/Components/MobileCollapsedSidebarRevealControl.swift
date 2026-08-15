import SwiftUI

struct MobileCollapsedSidebarRevealControl: View {
    let showSidebar: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                .accessibilityHidden(true)

            Button(action: showSidebar) {
                Image(systemName: "sidebar.left")
                    .frame(
                        width: CrestLayout.glassIconButtonDiameter,
                        height: CrestLayout.glassIconButtonDiameter
                    )
                    .contentShape(.circle)
            }
            .buttonBorderShape(.circle)
            .buttonStyle(.glass)
            .hoverEffect(.highlight)
            .help("Show Sidebar")
            .accessibilityLabel("Show Sidebar")
            .accessibilityHint("Also available by swiping inward from the leading edge")
            .accessibilityIdentifier("show-sidebar")
            .padding(MobileBrowserChromeLayout.collapsedSidebarControlPadding)
        }
    }
}

#Preview("Mobile Browser — Sidebar Reveal", traits: .fixedLayout(width: 120, height: 220)) {
    MobileCollapsedSidebarRevealControl(showSidebar: {})
}
