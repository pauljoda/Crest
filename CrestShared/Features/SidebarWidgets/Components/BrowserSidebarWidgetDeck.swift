import SwiftUI

struct BrowserSidebarWidgetDeck: View {
    let instances: [BrowserSidebarWidgetInstance]
    let selectedInstanceID: BrowserSidebarWidgetID?
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void
    let activateMediaSession: (BrowserTabRuntimeAssignment) -> Void
    let ownerFaviconData: (BrowserTabRuntimeAssignment) -> Data?
    let cycle: (BrowserSidebarWidgetCarouselDirection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeCardHeight: CGFloat?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        cardStack
            .frame(maxWidth: .infinity)
            .frame(height: activeCardHeight)
            .fixedSize(horizontal: false, vertical: activeCardHeight == nil)
            .padding(.bottom, reservedPeek)
            .contentShape(.rect)
            // Dragging takes precedence over card buttons; taps still reach them.
            .highPriorityGesture(deckDragGesture, including: .all)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Widget deck")
            .accessibilityValue(accessibilityValue)
            .accessibilityAction(named: "Previous Widget") { cycle(.previous) }
            .accessibilityAction(named: "Next Widget") { cycle(.next) }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    cycle(.next)
                case .decrement:
                    cycle(.previous)
                @unknown default:
                    break
                }
            }
            .animation(deckAnimation, value: selectedInstanceID)
            .animation(deckAnimation, value: activeCardHeight)
    }

    private var cardStack: some View {
        ZStack(alignment: .top) {
            ForEach(Array(deckOrder.enumerated()), id: \.element.id) { depth, instance in
                card(for: instance, depth: depth)
            }
        }
    }

    /// Separate containers prevent overlapping glass cards from merging.
    @ViewBuilder
    private func containedCard(
        for instance: BrowserSidebarWidgetInstance,
        depth: Int
    ) -> some View {
        if BrowserSidebarWidgetDeckStyle.usesLiquidGlass {
            GlassEffectContainer {
                presentedCard(for: instance, depth: depth)
            }
        } else {
            presentedCard(for: instance, depth: depth)
        }
    }

    private func presentedCard(
        for instance: BrowserSidebarWidgetInstance,
        depth: Int
    ) -> some View {
        BrowserSidebarWidgetCard(
            instance: instance,
            depth: depth,
            fixedHeight: depth == 0 ? nil : activeCardHeight,
            perform: perform,
            activateMediaSession: activateMediaSession,
            ownerFaviconData: ownerFaviconData
        )
    }

    private func card(
        for instance: BrowserSidebarWidgetInstance,
        depth: Int
    ) -> some View {
        let isFront = depth == 0
        return containedCard(for: instance, depth: depth)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { measuredHeight in
                updateActiveCardHeight(measuredHeight, isFront: isFront)
            }
            .scaleEffect(
                BrowserVisualAccessibilityPolicy.spatialScale(
                    BrowserSidebarWidgetDeckStyle.scale(forDepth: depth),
                    reduceMotion: reduceMotion
                ),
                anchor: .top
            )
            .offset(
                cardOffset(
                    forDepth: depth,
                    trackedTranslation: isFront ? dragOffset : 0
                )
            )
            .opacity(BrowserSidebarWidgetDeckStyle.opacity(forDepth: depth))
            .zIndex(Double(BrowserSidebarWidgetDeckStyle.visibleDepth - depth))
            .allowsHitTesting(isFront)
            .accessibilityHidden(!isFront)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: 0.97))
            )
    }

    private var deckOrder: [BrowserSidebarWidgetInstance] {
        BrowserSidebarWidgetCarouselPolicy.deckOrder(
            from: selectedInstanceID,
            in: instances,
            visibleDepth: BrowserSidebarWidgetDeckStyle.visibleDepth
        )
    }

    private var reservedPeek: CGFloat {
        CGFloat(BrowserSidebarWidgetDeckStyle.deckDepth(cardCount: instances.count))
            * BrowserSidebarWidgetDeckStyle.layerPeek
    }

    private var deckAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.spaceSwipe,
            reduceMotion: reduceMotion
        )
    }

    private var deckDragGesture: some Gesture {
        DragGesture(minimumDistance: CrestSpacing.small)
            .onChanged { value in
                guard instances.count > 1 else { return }
                dragOffset = BrowserSidebarWidgetDeckStyle.draggedOffset(
                    forTranslation: primaryTranslation(value.translation)
                )
            }
            .onEnded { value in
                let direction =
                    instances.count > 1
                    ? BrowserSidebarWidgetDeckStyle.dragCommitDirection(
                        translation: primaryTranslation(value.translation),
                        predictedEndTranslation: primaryTranslation(
                            value.predictedEndTranslation
                        )
                    )
                    : nil
                withAnimation(deckAnimation) {
                    dragOffset = 0
                    if let direction { cycle(direction) }
                }
            }
    }

    private func primaryTranslation(_ translation: CGSize) -> CGFloat {
        BrowserSidebarWidgetDeckGesturePolicy.primaryTranslation(
            horizontal: translation.width,
            vertical: translation.height,
            axis: BrowserSidebarWidgetDeckGesturePolicy.currentPlatformAxis
        )
    }

    private func cardOffset(
        forDepth depth: Int,
        trackedTranslation: CGFloat
    ) -> CGSize {
        BrowserSidebarWidgetDeckGesturePolicy.cardOffset(
            trackedTranslation: trackedTranslation,
            slotOffset: slotOffset(forDepth: depth),
            axis: BrowserSidebarWidgetDeckGesturePolicy.currentPlatformAxis
        )
    }

    private var accessibilityValue: String {
        guard
            let selectedInstanceID,
            let selectedIndex = instances.firstIndex(where: { $0.id == selectedInstanceID })
        else {
            return "\(instances.count) widgets"
        }
        return "Widget \(selectedIndex + 1) of \(instances.count)"
    }

    private func slotOffset(forDepth depth: Int) -> CGFloat {
        BrowserSidebarWidgetDeckStyle.slotOffset(
            forDepth: depth,
            cardHeight: activeCardHeight
        )
    }

    private func updateActiveCardHeight(
        _ measuredHeight: CGFloat,
        isFront: Bool
    ) {
        guard
            BrowserSidebarWidgetCarouselLayoutPolicy.shouldUpdateActiveCardHeight(
                currentHeight: activeCardHeight,
                measuredHeight: measuredHeight,
                isSelected: isFront
            )
        else { return }
        activeCardHeight = measuredHeight
    }
}
