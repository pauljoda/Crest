import SwiftUI

struct BrowserSidebarResizeHandle: View {
    // MARK: - Variables

    @Binding var width: CGFloat
    var onResizeEnded: (CGFloat) -> Void = { _ in }
    var edge: HorizontalEdge = .leading

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragStartWidth: CGFloat?
    @State private var isActive = false
    /// Whether the drag is still under way. A drag the system cancels never
    /// ends, so this answers for it when it resets.
    @GestureState private var isDragging = false

    // MARK: - Actions - Presentation

    var body: some View {
        Color.clear
            .frame(width: BrowserSidebarResizeHandleMetrics.hitWidth)
            .contentShape(.rect)
            .modifier(BrowserPlatformColumnResizePointerModifier())
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
                // The handle moves as width changes; measure in stationary coordinates.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($isDragging) { _, isDragging, _ in isDragging = true }
                    .onChanged(resize)
                    .onEnded(endResize)
            )
            .onChange(of: isDragging) { _, isDragging in
                // A cancelled drag still settles the width it reached, so the
                // resize it began is never left open.
                guard !isDragging, dragStartWidth != nil else { return }
                finishResize()
            }
            // So does a drag whose handle goes away under it, as when the
            // sidebar is put away mid-drag.
            .onDisappear {
                guard dragStartWidth != nil else { return }
                finishResize()
            }
            .accessibilityLabel("Resize Sidebar")
            .accessibilityValue("\(Int(width.rounded())) points")
            .accessibilityAdjustableAction(adjustWidth)
    }

    // MARK: - Actions - Resize

    private func resize(_ value: DragGesture.Value) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            let start = dragStartWidth ?? width
            dragStartWidth = start
            isActive = true
            width = BrowserChromeLayout.clampedSidebarWidth(
                start
                    + layoutDirection.sidebarResizeDelta(value.translation.width) * (edge == .leading ? 1 : -1)
            )
        }
    }

    private func endResize(_ value: DragGesture.Value) {
        resize(value)
        finishResize()
    }

    private func finishResize() {
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
