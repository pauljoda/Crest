import SwiftUI

struct BrowserRootShellControls: View {
    let model: BrowserRootModel
    @Binding var storedSidebarWidth: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    @ViewBuilder
    var body: some View {
        switch model.sidebarPresentation {
        case .collapsed:
            CollapsedSidebarRevealControl(
                showSidebar: {
                    model.presentFloatingSidebar(reduceMotion: reduceMotion)
                }
            )
        case .docked:
            BrowserSidebarResizeHandle(
                width: model.sidebarWidthBinding,
                onResizeEnded: commitSidebarWidth
            )
            .offset(
                x: BrowserChromeDirectionPolicy.leadingOffset(
                    model.sidebarWidth
                        - BrowserRootMetrics.sidebarResizeHandleOffset,
                    layoutDirection: layoutDirection
                )
            )
            .zIndex(BrowserRootMetrics.sidebarResizeControlZIndex)
        case .floating:
            EmptyView()
        }
    }

    private func commitSidebarWidth(_ width: CGFloat) {
        guard let committedWidth = model.commitSidebarWidth(width) else { return }
        storedSidebarWidth = Double(committedWidth)
    }
}

#Preview("Browser Root Shell Controls") {
    @Previewable @State var sidebarWidth = Double(
        BrowserChromeLayout.sidebarIdealWidth
    )
    BrowserRootShellControls(
        model: BrowserRootPreviewFixture.makeModel(),
        storedSidebarWidth: $sidebarWidth
    )
    .frame(width: 600, height: 400)
}
