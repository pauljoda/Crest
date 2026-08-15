import SwiftUI

/// The affordance that moves one boundary between two split cards.
///
/// It lives in the gap between the cards and overhangs each of them slightly,
/// so the pointer target is comfortable without the control ever covering
/// content. The drag reports its total travel rather than each frame's step —
/// which is what `BrowserSplitWidthTransaction.resize(dividerIndex:delta:containerWidth:)`
/// expects — and the durable per-window record advances once, on release.
///
/// That travel is measured in `BrowserSplitResizeSpace`, the columns row, and
/// never in the handle's own space. The row positions this handle from the
/// fractions the drag writes, so the handle's frame moves with the boundary and
/// a translation measured against it reports the pointer's travel minus its own
/// — a feedback loop that halves tracking and turns a point of pointer noise
/// into a standing oscillation.
///
/// The capsule only appears once a drag owns the handle, so the affordance a
/// pointer gets beforehand is the pointer itself:
/// `BrowserPlatformColumnResizePointerModifier` gives each platform its own
/// answer to "this boundary moves" rather than leaving it to be discovered.
struct BrowserSplitCardResizeHandle: View {
    /// The gap this handle sits in: the one after the card at this index.
    let dividerIndex: Int
    /// The drag's travel since it began, measured toward the trailing edge in
    /// the reading direction.
    let resize: (CGFloat) -> Void
    let commit: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isDragging = false

    var body: some View {
        Color.clear
            .frame(width: BrowserSplitLayoutMetrics.resizeHandleHitWidth)
            .contentShape(.rect)
            .modifier(BrowserPlatformColumnResizePointerModifier())
            .overlay {
                Capsule()
                    .fill(
                        .primary.opacity(
                            isDragging
                                ? BrowserSplitCardResizeHandleMetrics.activeIndicatorOpacity
                                : 0
                        )
                    )
                    .frame(
                        width: BrowserSplitCardResizeHandleMetrics.indicatorWidth,
                        height: BrowserSplitCardResizeHandleMetrics.indicatorHeight
                    )
                    .accessibilityHidden(true)
            }
            .gesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: BrowserSplitResizeSpace.coordinateSpace
                )
                .onChanged(dragChanged)
                .onEnded(dragEnded)
            )
            .accessibilityLabel("Resize Split View Columns")
            .accessibilityValue("Divider \(dividerIndex + 1)")
            .accessibilityAdjustableAction(adjustWidth)
    }

    private func dragChanged(_ value: DragGesture.Value) {
        isDragging = true
        resize(semanticTranslation(value.translation.width))
    }

    private func dragEnded(_ value: DragGesture.Value) {
        isDragging = false
        resize(semanticTranslation(value.translation.width))
        commit()
    }

    /// Each accessibility step is its own complete interaction: it resizes and
    /// commits, so the next step measures from the layout now on screen.
    private func adjustWidth(_ direction: AccessibilityAdjustmentDirection) {
        let step = BrowserSplitCardResizeHandleMetrics.accessibilityStep
        let delta: CGFloat
        switch direction {
        case .increment:
            delta = step
        case .decrement:
            delta = -step
        @unknown default:
            delta = 0
        }
        guard delta != 0 else { return }
        resize(delta)
        commit()
    }

    private func semanticTranslation(_ translation: CGFloat) -> CGFloat {
        BrowserChromeDirectionPolicy.semanticHorizontalTranslation(
            translation,
            layoutDirection: layoutDirection
        )
    }
}

#Preview("Split Card Resize Handle") {
    @Previewable @State var transaction = BrowserSplitWidthTransaction(
        persistedFractions: [0.5, 0.5]
    )

    HStack(spacing: 0) {
        Color.gray.opacity(0.2)
        BrowserSplitCardResizeHandle(
            dividerIndex: 0,
            resize: { delta in
                transaction.resize(
                    dividerIndex: 0,
                    delta: delta,
                    containerWidth: 520
                )
            },
            commit: { _ = transaction.commit() }
        )
        Color.gray.opacity(0.2)
    }
    .frame(width: 520, height: 180)
    // The row the handle measures its drag against, declared here for the same
    // reason `BrowserSplitColumnsView` declares it: the gesture resolves against
    // a container, never against the handle.
    .coordinateSpace(BrowserSplitResizeSpace.coordinateSpace)
}
