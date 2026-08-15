import SwiftUI

struct BrowserUtilityFanControl: View {
    let isExpanded: Bool
    let origin: CGPoint
    let destination: CGPoint
    let selectedSurface: BrowserUtilitySurface?
    let badgeColor: Color
    let downloads: [BrowserDownloadItem]
    let newDownloadCount: Int
    let select: (BrowserUtilitySurface) -> Void
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedSurfaces: Set<BrowserUtilitySurface> = []
    @State private var isContainerVisible = false
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: BrowserUtilitySwitcherLayout.spacing) {
            ZStack {
                ForEach(
                    BrowserUtilitySwitcherLayout.destinations.enumerated(),
                    id: \.element
                ) { index, surface in
                    let isRevealed = revealedSurfaces.contains(surface)
                    let destinationPosition = CGPoint(
                        x: destination.x,
                        y: destination.y
                            + BrowserUtilitySwitcherLayout.verticalOffset(
                                for: index,
                                count: BrowserUtilitySwitcherLayout.destinations.count
                            )
                    )
                    BrowserUtilityFanDestinationButton(
                        surface: surface,
                        selectedSurface: selectedSurface,
                        badgeColor: badgeColor,
                        downloads: downloads,
                        newDownloadCount: newDownloadCount,
                        glassNamespace: glassNamespace,
                        select: select
                    )
                    .scaleEffect(
                        isRevealed ? 1 : BrowserUtilitySwitcherLayout.collapsedScale
                    )
                    .opacity(isRevealed ? 1 : 0)
                    .position(destinationPosition)
                    .offset(
                        x: isRevealed ? 0 : origin.x - destinationPosition.x,
                        y: isRevealed ? 0 : origin.y - destinationPosition.y
                    )
                    .allowsHitTesting(isExpanded && isRevealed)
                    .accessibilityHidden(!isExpanded || !isRevealed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isContainerVisible ? 1 : 0)
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .task(id: isExpanded) {
            await updatePresentation()
        }
    }

    @MainActor
    private func updatePresentation() async {
        let shouldReduceMotion = reduceMotionOverride ?? reduceMotion
        if shouldReduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                revealedSurfaces =
                    isExpanded
                    ? Set(BrowserUtilitySwitcherLayout.destinations)
                    : []
                isContainerVisible = isExpanded
            }
            return
        }

        if isExpanded {
            var initialTransaction = Transaction()
            initialTransaction.disablesAnimations = true
            withTransaction(initialTransaction) {
                revealedSurfaces.removeAll()
                isContainerVisible = true
            }
            await Task.yield()

            for (index, surface) in BrowserUtilitySwitcherLayout.destinations.enumerated() {
                if index > 0 {
                    try? await Task.sleep(
                        for: .seconds(BrowserUtilitySwitcherLayout.staggerInterval)
                    )
                }
                guard !Task.isCancelled else { return }
                withAnimation(
                    BrowserVisualAccessibilityPolicy.animation(
                        CrestMotion.utilityFanReveal,
                        reduceMotion: shouldReduceMotion
                    )
                ) {
                    _ = revealedSurfaces.insert(surface)
                }
            }
        } else {
            for (index, surface) in BrowserUtilitySwitcherLayout.destinations
                .reversed()
                .enumerated()
            {
                if index > 0 {
                    try? await Task.sleep(
                        for: .seconds(BrowserUtilitySwitcherLayout.staggerInterval * 0.55)
                    )
                }
                guard !Task.isCancelled else { return }
                _ = withAnimation(
                    BrowserVisualAccessibilityPolicy.animation(
                        CrestMotion.utilityFanDismiss,
                        reduceMotion: shouldReduceMotion
                    )
                ) {
                    revealedSurfaces.remove(surface)
                }
            }
            try? await Task.sleep(for: CrestMotion.utilityFanDismissCompletionDelay)
            guard !Task.isCancelled else { return }
            isContainerVisible = false
        }
    }

}

#Preview("Expanded Utility Fan", traits: .fixedLayout(width: 180, height: 260)) {
    @Previewable @State var selectedSurface: BrowserUtilitySurface? = .history

    BrowserUtilityFanControl(
        isExpanded: true,
        origin: CGPoint(x: 24, y: 130),
        destination: CGPoint(x: 90, y: 130),
        selectedSurface: selectedSurface,
        badgeColor: .indigo,
        downloads: [
            BrowserUtilityListPreviewFixture.activeDownload,
            BrowserUtilityListPreviewFixture.failedDownload,
        ],
        newDownloadCount: 2,
        select: { selectedSurface = $0 },
        reduceMotionOverride: true
    )
}
