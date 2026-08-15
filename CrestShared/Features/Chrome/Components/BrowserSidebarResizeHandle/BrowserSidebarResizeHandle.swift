import SwiftUI

struct BrowserSidebarResizeHandle: View {
    @Binding var width: CGFloat
    var onResizeEnded: (CGFloat) -> Void = { _ in }

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragStartWidth: CGFloat?
    @State private var isActive = false

    var body: some View {
        Color.clear
            .frame(width: BrowserSidebarResizeHandleMetrics.hitWidth)
            .contentShape(.rect)
            .overlay {
                Capsule()
                    .fill(
                        .primary.opacity(
                            isActive
                                ? BrowserSidebarResizeHandleMetrics.activeIndicatorOpacity
                                : 0
                        )
                    )
                    .frame(
                        width: BrowserSidebarResizeHandleMetrics.indicatorWidth,
                        height: BrowserSidebarResizeHandleMetrics.indicatorHeight
                    )
                    .accessibilityHidden(true)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(resize)
                    .onEnded(endResize)
            )
            .accessibilityLabel("Resize Sidebar")
            .accessibilityValue("\(Int(width.rounded())) points")
            .accessibilityAdjustableAction(adjustWidth)
    }

    private func resize(_ value: DragGesture.Value) {
        let start = dragStartWidth ?? width
        dragStartWidth = start
        isActive = true
        width = BrowserChromeLayout.clampedSidebarWidth(
            start
                + BrowserChromeDirectionPolicy.sidebarResizeDelta(
                    value.translation.width,
                    layoutDirection: layoutDirection
                )
        )
    }

    private func endResize(_: DragGesture.Value) {
        dragStartWidth = nil
        isActive = false
        onResizeEnded(width)
    }

    private func adjustWidth(_ direction: AccessibilityAdjustmentDirection) {
        let delta: CGFloat
        switch direction {
        case .increment:
            delta = BrowserSidebarResizeHandleMetrics.accessibilityStep
        case .decrement:
            delta = -BrowserSidebarResizeHandleMetrics.accessibilityStep
        @unknown default:
            delta = 0
        }
        guard delta != 0 else { return }
        width = BrowserChromeLayout.clampedSidebarWidth(width + delta)
        onResizeEnded(width)
    }
}

#Preview("Sidebar Resize Handle") {
    @Previewable @State var width = BrowserChromeLayout.sidebarIdealWidth

    HStack(spacing: 0) {
        Text("Sidebar")
            .frame(width: width, height: 180)
            .background(.quaternary)

        BrowserSidebarResizeHandle(width: $width)

        Text("Page")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }
    .frame(width: 520, height: 180)
}

#Preview("Sidebar Resize Handle — Right to Left") {
    @Previewable @State var width = BrowserChromeLayout.sidebarIdealWidth

    HStack(spacing: 0) {
        Text("Sidebar")
            .frame(width: width, height: 180)
            .background(.quaternary)

        BrowserSidebarResizeHandle(width: $width)

        Text("Page")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }
    .frame(width: 520, height: 180)
    .environment(\.layoutDirection, .rightToLeft)
}
