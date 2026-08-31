import ImageIO
import SwiftUI

extension EnvironmentValues {
    @Entry var browserSidebarWidgetRuntime: BrowserSidebarWidgetRuntime? = nil
    @Entry var browserApplicationIcon: Image? = nil
}

/// Geometry and finish shared by every card in the sidebar widget deck.
///
/// The deck is a vertical stack of real cards the reader flips through, so one
/// place owns the slot transforms, the card stock treatment, and the gesture
/// thresholds rather than scattering them across the presentation views.
enum BrowserSidebarWidgetDeckStyle {
    /// Experiment seam. `true` hands the card's surface, edge, and depth to system
    /// Liquid Glass, each card inside its own `GlassEffectContainer`; `false` keeps
    /// Crest's hand-rolled material, edge highlight, wash, and dual shadow. Both
    /// treatments stay in the tree while the choice is being evaluated.
    static let usesLiquidGlass = true

    static let cardStrokeWidth: CGFloat = 0.5
    static let edgeHighlightTopOpacity = 0.22
    static let edgeHighlightBottomOpacity = 0.05
    static let contactShadowOpacity = 0.22
    static let contactShadowRadius: CGFloat = 1
    static let contactShadowOffset: CGFloat = 0.5
    static let ambientShadowRadius: CGFloat = 8
    static let ambientShadowOffset: CGFloat = 3
    static let underCardShadowScale = 0.45

    /// Visible slots: the front card plus the two cards it will flip to.
    static let visibleDepth = 3
    static let layerPeek: CGFloat = 6
    static let depthScales: [CGFloat] = [1, 0.965, 0.93]
    static let depthOpacities: [Double] = [1, 0.9, 0.75]
    static let contentOpacities: [Double] = [1, 0.45, 0]
    static let contentMaskFadeStart = 0.55
    static let contentMaskFadeEnd = 0.85

    static let dragTrackingFactor: CGFloat = 0.35
    static let dragRubberBandLimit: CGFloat = 28
    static let dragCommitThreshold: CGFloat = 40

    static let contentSpacing: CGFloat = 10
    static let nowPlayingSectionSpacing: CGFloat = 6
    /// Media remains the visual anchor on both pointer and touch platforms.
    /// Touch chrome gets a little more image area without coupling the shared
    /// card to a device family.
    static var artworkSize: CGFloat {
        max(50, CrestLayout.minimumHitTarget + 12)
    }
    static let artworkCornerRadius: CGFloat = 6
    static let hairlineStrokeOpacity = 0.1
    static let faviconSize = 22.0
    static let focalControlDiameter: CGFloat = 32
    /// Drawn size of a quiet glyph control, held constant across platforms so the
    /// transport reads as small circles flanking the larger focal one.
    static let quietControlDiameter: CGFloat = 24
    static let quietControlSymbolSize: CGFloat = 12
    /// The independently accessible target around that circle.
    static var quietControlHitTarget: CGFloat {
        max(quietControlDiameter, CrestLayout.minimumHitTarget)
    }
    static let actionHeight: CGFloat = 32
    static let headerTileSize: CGFloat = 30
    static let badgeVerticalPadding: CGFloat = 1
    static let stepperBadgeHorizontalPadding: CGFloat = 2
    static let indicatorDotDiameter: CGFloat = 5
    static let indicatorHitWidth: CGFloat = 24
    static let indicatorHitHeight: CGFloat = 24
    static let indicatorDotHitHeight: CGFloat = 16
    static let sideStepperRailWidth: CGFloat = 24
    /// The card keeps the exact width it has with one widget. The rail moves into
    /// the sidebar's trailing pane margin so its visible marks sit between the
    /// card and page while the larger invisible target may straddle that seam.
    static let sideStepperExternalOffset = sideStepperOffset(
        cardTrailingInset: CrestSpacing.small,
        railWidth: sideStepperRailWidth,
        paneBoundaryWidth: CrestLayout.hairline
    )
    static let indicatorActiveOpacity = 0.72
    static let indicatorInactiveOpacity = 0.3

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CrestRadius.card, style: .continuous)
    }

    /// A glass top-edge highlight that fades into the card's lower border.
    static func edgeHighlight(scale: Double = 1) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.primary.opacity(edgeHighlightTopOpacity * scale),
                Color.primary.opacity(edgeHighlightBottomOpacity * scale),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var quietControlSymbolFont: Font {
        .system(size: quietControlSymbolSize, weight: .semibold)
    }

    /// Page indicators never change their occupied geometry as selection moves.
    /// Selection is communicated by the system-standard tint contrast instead.
    static func indicatorSize(isSelected _: Bool) -> CGSize {
        CGSize(width: indicatorDotDiameter, height: indicatorDotDiameter)
    }

    /// Converts trailing alignment into the midpoint between the card's visible
    /// edge and the far edge of the shared sidebar/page hairline.
    static func sideStepperOffset(
        cardTrailingInset: CGFloat,
        railWidth: CGFloat,
        paneBoundaryWidth: CGFloat
    ) -> CGFloat {
        (railWidth - cardTrailingInset + paneBoundaryWidth) / 2
    }

    static func deckDepth(cardCount: Int) -> Int {
        min(max(cardCount - 1, 0), visibleDepth - 1)
    }

    static func scale(forDepth depth: Int) -> CGFloat {
        depthScales[min(max(depth, 0), depthScales.count - 1)]
    }

    static func opacity(forDepth depth: Int) -> Double {
        depthOpacities[min(max(depth, 0), depthOpacities.count - 1)]
    }

    static func contentOpacity(forDepth depth: Int) -> Double {
        contentOpacities[min(max(depth, 0), contentOpacities.count - 1)]
    }

    /// Only a card behind the front one is masked. The front card's content is
    /// left completely untouched, so nothing can reach its rendering or its hit
    /// testing — including mid-drag, where the front card keeps depth 0.
    static func masksContent(forDepth depth: Int) -> Bool {
        depth > 0
    }

    /// A card behind the front one is clamped to the front card's height, so its
    /// controls would otherwise be sliced mid-glyph at the clip edge and show
    /// through the peek band. Its content fades out before that edge instead.
    static var contentMask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: contentMaskFadeStart),
                .init(color: .clear, location: contentMaskFadeEnd),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Under-cards are drawn at the front card's height and scaled from their top
    /// edge, so the slot offset has to absorb the shrink for the peek below the
    /// front card to stay a predictable `layerPeek` per layer.
    static func slotOffset(forDepth depth: Int, cardHeight: CGFloat?) -> CGFloat {
        guard depth > 0 else { return 0 }
        let peek = layerPeek * CGFloat(depth)
        let shrink = (cardHeight ?? 0) * (1 - scale(forDepth: depth))
        return peek + shrink
    }

    /// Tracks the finger at a fraction of its primary-axis travel and softens
    /// past the limit so the deck never slides away from the sidebar.
    static func draggedOffset(forTranslation translation: CGFloat) -> CGFloat {
        let tracked = translation * dragTrackingFactor
        let magnitude = abs(tracked)
        guard magnitude > dragRubberBandLimit else { return tracked }
        let excess = magnitude - dragRubberBandLimit
        let damped =
            dragRubberBandLimit + excess / (1 + excess / dragRubberBandLimit)
        return tracked < 0 ? -damped : damped
    }

    /// A negative primary-axis drag flips forward; a positive drag flips back.
    static func dragCommitDirection(
        translation: CGFloat,
        predictedEndTranslation: CGFloat
    ) -> BrowserSidebarWidgetCarouselDirection? {
        let travel: CGFloat
        if abs(translation) >= dragCommitThreshold {
            travel = translation
        } else if abs(predictedEndTranslation) >= dragCommitThreshold {
            travel = predictedEndTranslation
        } else {
            return nil
        }
        return travel < 0 ? .next : .previous
    }
}

/// The sidebar's widget layer.
///
/// One deck serves every Space of every profile: it takes no profile, and its
/// body renders nothing while there is nothing to show, so an embed site can
/// mount it unconditionally and a Space switch can never unmount it.
struct BrowserSidebarWidgetHost: View {
    let capabilities: BrowserSidebarWidgetCapabilities
    let activateMediaSession: (BrowserTabRuntimeAssignment) -> Void
    let ownerFaviconData: (BrowserTabRuntimeAssignment) -> Data?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserSidebarWidgetRuntime) private var runtime
    @State private var visibleInstanceID: BrowserSidebarWidgetID?

    var body: some View {
        if !instances.isEmpty {
            let cardInsets = BrowserSidebarWidgetCarouselLayoutPolicy.cardInsets(
                instanceCount: instances.count
            )
            BrowserSidebarWidgetDeck(
                instances: instances,
                selectedInstanceID: visibleInstanceID,
                perform: perform,
                activateMediaSession: activateMediaSession,
                ownerFaviconData: ownerFaviconData,
                cycle: cycle
            )
            .padding(.leading, cardInsets.leading)
            .padding(.trailing, cardInsets.trailing)
            .padding(.horizontal, CrestSpacing.small)
            .overlay(alignment: .trailing) {
                if instances.count > 1 {
                    BrowserSidebarWidgetDeckStepper(
                        instances: instances,
                        selectedInstanceID: visibleInstanceID,
                        select: select,
                        cycle: cycle
                    )
                    .frame(width: BrowserSidebarWidgetDeckStyle.sideStepperRailWidth)
                    .offset(
                        x: BrowserSidebarWidgetDeckStyle.sideStepperExternalOffset
                    )
                }
            }
            .padding(.top, CrestSpacing.small)
            .padding(.bottom, CrestSpacing.extraSmall)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sidebar Widgets")
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .move(edge: .bottom))
            )
            .onChange(of: instanceIDs, initial: true) {
                reconcileSelection()
            }
            .onChange(of: runtimeSelection) { _, selectedID in
                guard selectedID != visibleInstanceID else { return }
                withAnimation(deckAnimation) {
                    visibleInstanceID = selectedID
                }
            }
            .onChange(of: visibleInstanceID) { _, selectedID in
                guard let selectedID, selectedID != runtimeSelection else {
                    return
                }
                runtime?.selectCarouselInstance(
                    selectedID,
                    visibleInstances: instances
                )
            }
        }
    }

    private var instances: [BrowserSidebarWidgetInstance] {
        runtime?.instances(capabilities: capabilities) ?? []
    }

    private var instanceIDs: [BrowserSidebarWidgetID] {
        instances.map(\.id)
    }

    private var runtimeSelection: BrowserSidebarWidgetID? {
        runtime?.carouselSelection
    }

    private var deckAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.spaceSwipe,
            reduceMotion: reduceMotion
        )
    }

    private func reconcileSelection() {
        withAnimation(deckAnimation) {
            runtime?.reconcileCarouselSelection(visibleInstances: instances)
            visibleInstanceID = runtime?.carouselSelection ?? instances.first?.id
        }
    }

    private func select(_ instanceID: BrowserSidebarWidgetID) {
        guard instanceID != visibleInstanceID else { return }
        withAnimation(deckAnimation) {
            runtime?.selectCarouselInstance(
                instanceID,
                visibleInstances: instances
            )
            visibleInstanceID = instanceID
        }
    }

    private func cycle(_ direction: BrowserSidebarWidgetCarouselDirection) {
        guard
            let nextID = BrowserSidebarWidgetCarouselPolicy.cyclicAdjacentID(
                to: visibleInstanceID,
                in: instances,
                direction: direction
            )
        else { return }
        select(nextID)
    }

    private func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {
        runtime?.perform(action, on: instanceID)
    }
}

private struct BrowserSidebarWidgetDeck: View {
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
            // Once movement crosses the deck threshold, card navigation wins
            // over every child button. A stationary tap never recognizes this
            // drag and therefore reaches the explicit control underneath it.
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

    /// Each card owns its own `GlassEffectContainer`: the deck's cards overlap
    /// by construction, and glass shapes sharing one container merge on contact,
    /// fusing the stack into a single blob.
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

private struct BrowserSidebarWidgetDeckStepper: View {
    let instances: [BrowserSidebarWidgetInstance]
    let selectedInstanceID: BrowserSidebarWidgetID?
    let select: (BrowserSidebarWidgetID) -> Void
    let cycle: (BrowserSidebarWidgetCarouselDirection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            fullPageIndicator
            compactStepper
        }
        .frame(width: BrowserSidebarWidgetDeckStyle.sideStepperRailWidth)
        .focusable(interactions: .activate)
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            switch press.key {
            case .leftArrow, .upArrow:
                cycle(.previous)
            case .rightArrow, .downArrow:
                cycle(.next)
            default:
                return .ignored
            }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose sidebar widget")
        .accessibilityValue(selectionValue)
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
    }

    @ViewBuilder private var fullPageIndicator: some View {
        #if os(iOS)
            BrowserSidebarWidgetVerticalPageControl(
                numberOfPages: instances.count,
                currentPage: selectedIndex,
                selectPage: selectPage
            )
        #else
            indicatorColumn
        #endif
    }

    private var indicatorColumn: some View {
        VStack(spacing: 0) {
            ForEach(instances) { instance in
                indicator(for: instance)
            }
        }
        .animation(selectionAnimation, value: selectedInstanceID)
    }

    private func indicator(
        for instance: BrowserSidebarWidgetInstance
    ) -> some View {
        let isSelected = instance.id == selectedInstanceID
        let indicatorSize = BrowserSidebarWidgetDeckStyle.indicatorSize(
            isSelected: isSelected
        )
        return Button {
            select(instance.id)
        } label: {
            Circle()
                .fill(
                    isSelected
                        ? Color.primary.opacity(
                            BrowserSidebarWidgetDeckStyle.indicatorActiveOpacity
                        )
                        : Color.secondary.opacity(
                            BrowserSidebarWidgetDeckStyle.indicatorInactiveOpacity
                        )
                )
                .frame(
                    width: indicatorSize.width,
                    height: indicatorSize.height
                )
                .frame(
                    minWidth: BrowserSidebarWidgetDeckStyle.indicatorHitWidth,
                    minHeight: BrowserSidebarWidgetDeckStyle.indicatorDotHitHeight
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(indicatorLabel(for: instance))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedIndex: Int {
        guard
            let selectedInstanceID,
            let index = instances.firstIndex(where: { $0.id == selectedInstanceID })
        else { return 0 }
        return index
    }

    private func selectPage(_ index: Int) {
        guard instances.indices.contains(index) else { return }
        select(instances[index].id)
    }

    private var compactStepper: some View {
        VStack(spacing: 0) {
            stepButton(.previous, symbol: "chevron.up")
            Text(verbatim: compactSelectionValue)
                .font(CrestTypography.compactMetadata.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(
                    .horizontal,
                    BrowserSidebarWidgetDeckStyle.stepperBadgeHorizontalPadding
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .background(.quaternary, in: .capsule)
            stepButton(.next, symbol: "chevron.down")
        }
    }

    private var selectionValue: String {
        guard
            let selectedInstanceID,
            let selectedIndex = instances.firstIndex(where: { $0.id == selectedInstanceID })
        else { return "\(instances.count) widgets" }
        return "\(selectedIndex + 1) of \(instances.count)"
    }

    private var compactSelectionValue: String {
        guard
            let selectedInstanceID,
            let selectedIndex = instances.firstIndex(where: { $0.id == selectedInstanceID })
        else { return "\(instances.count)" }
        return "\(selectedIndex + 1)/\(instances.count)"
    }

    private var selectionAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.selection,
            reduceMotion: reduceMotion
        )
    }

    /// The deck wraps, so a step control is never a dead end.
    private func stepButton(
        _ direction: BrowserSidebarWidgetCarouselDirection,
        symbol: String
    ) -> some View {
        Button {
            cycle(direction)
        } label: {
            Image(systemName: symbol)
                .frame(
                    minWidth: BrowserSidebarWidgetDeckStyle.indicatorHitWidth,
                    minHeight: BrowserSidebarWidgetDeckStyle.indicatorHitHeight
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            direction == .previous ? "Previous Widget" : "Next Widget"
        )
    }

    private func indicatorLabel(
        for instance: BrowserSidebarWidgetInstance
    ) -> String {
        let position =
            instances.firstIndex(where: { $0.id == instance.id })
            .map { $0 + 1 } ?? 1
        switch instance.presentation {
        case .nowPlaying(let session):
            return "Widget \(position), Now Playing, \(session.ownerDisplayTitle)"
        case .softwareUpdate:
            return "Widget \(position), Update Available"
        }
    }
}

private struct BrowserSidebarWidgetCard: View {
    let instance: BrowserSidebarWidgetInstance
    /// 0 is the card in front. Depth drives the content fade, not the card's own
    /// surface: the chrome behind stays fully drawn at every slot.
    let depth: Int
    /// Under-cards share the front card's height so the deck reads as one stack
    /// of identical stock rather than cards of assorted sizes.
    let fixedHeight: CGFloat?
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void
    let activateMediaSession: (BrowserTabRuntimeAssignment) -> Void
    let ownerFaviconData: (BrowserTabRuntimeAssignment) -> Data?

    var body: some View {
        presentation
            .padding(CrestSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: fixedHeight, alignment: .top)
            .opacity(BrowserSidebarWidgetDeckStyle.contentOpacity(forDepth: depth))
            .modifier(BrowserSidebarWidgetCardContentFade(depth: depth))
            .clipShape(BrowserSidebarWidgetDeckStyle.cardShape)
            .modifier(BrowserSidebarWidgetCardChrome(depth: depth))
            .contentShape(BrowserSidebarWidgetDeckStyle.cardShape)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var presentation: some View {
        switch instance.presentation {
        case .nowPlaying(let session):
            BrowserNowPlayingSidebarWidget(
                instance: instance,
                session: session,
                faviconData: ownerFaviconData(session.owner),
                perform: perform,
                activate: activateMediaSession
            )
        case .softwareUpdate(let update):
            BrowserSoftwareUpdateSidebarWidget(
                instance: instance,
                update: update,
                perform: perform
            )
        }
    }

}

/// Fades a receding card's controls out before the clip edge they would otherwise
/// be sliced at. The front card is returned untouched.
private struct BrowserSidebarWidgetCardContentFade: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {
        if BrowserSidebarWidgetDeckStyle.masksContent(forDepth: depth) {
            content.mask { BrowserSidebarWidgetDeckStyle.contentMask }
        } else {
            content
        }
    }
}

/// The card's surface. Under Liquid Glass the system owns the fill, the edge, and
/// the depth, so Crest draws none of it; the hand-rolled treatment stays behind
/// the same seam for comparison.
private struct BrowserSidebarWidgetCardChrome: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {
        if BrowserSidebarWidgetDeckStyle.usesLiquidGlass {
            content.glassEffect(
                .regular,
                in: BrowserSidebarWidgetDeckStyle.cardShape
            )
        } else {
            crestChrome(content)
        }
    }

    private func crestChrome(_ content: Content) -> some View {
        content
            .background(CrestColor.chromeSurface, in: BrowserSidebarWidgetDeckStyle.cardShape)
            .background(.regularMaterial, in: BrowserSidebarWidgetDeckStyle.cardShape)
            .overlay {
                BrowserSidebarWidgetDeckStyle.cardShape
                    .stroke(
                        BrowserSidebarWidgetDeckStyle.edgeHighlight(scale: chromeScale),
                        lineWidth: BrowserSidebarWidgetDeckStyle.cardStrokeWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(
                    BrowserSidebarWidgetDeckStyle.contactShadowOpacity * chromeScale
                ),
                radius: BrowserSidebarWidgetDeckStyle.contactShadowRadius,
                y: BrowserSidebarWidgetDeckStyle.contactShadowOffset
            )
            .shadow(
                color: .black.opacity(CrestOpacity.controlShadow * chromeScale),
                radius: BrowserSidebarWidgetDeckStyle.ambientShadowRadius,
                y: BrowserSidebarWidgetDeckStyle.ambientShadowOffset
            )
    }

    private var chromeScale: Double {
        depth == 0 ? 1 : BrowserSidebarWidgetDeckStyle.underCardShadowScale
    }
}

private struct BrowserNowPlayingSidebarWidget: View {
    let instance: BrowserSidebarWidgetInstance
    let session: BrowserMediaSessionSnapshot
    let faviconData: Data?
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void
    let activate: (BrowserTabRuntimeAssignment) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var artworkSize =
        BrowserSidebarWidgetDeckStyle.artworkSize
    @ScaledMetric(relativeTo: .footnote) private var faviconSize =
        BrowserSidebarWidgetDeckStyle.faviconSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            mediaIdentityButton
                .padding(
                    .top,
                    BrowserSidebarWidgetDeckStyle.nowPlayingSectionSpacing
                )
            transportRow
                .padding(
                    .top,
                    BrowserSidebarWidgetDeckStyle.nowPlayingSectionSpacing
                )
        }
        .overlay(alignment: .topTrailing) {
            // A full touch target remains available without making the title
            // row 44 points tall or visually inflating the card on iPad.
            dismissButton
        }
        .padding(.top, -CrestSpacing.extraSmall)
        .accessibilityLabel("Now Playing")
    }

    /// The stable Crest tab title is independent of page playback metadata. The
    /// dismiss control is overlaid separately so the ✕ can never activate the
    /// tab or dictate the title row's height.
    private var headerRow: some View {
        Button {
            showOwner()
        } label: {
            Text(verbatim: session.ownerDisplayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(
                    minHeight: BrowserSidebarWidgetDeckStyle.quietControlDiameter,
                    alignment: .leading
                )
                .padding(
                    .trailing,
                    BrowserSidebarWidgetDeckStyle.quietControlDiameter
                        + CrestSpacing.extraSmall
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show tab \(session.ownerDisplayTitle)")
        .help("Show Tab")
    }

    private var mediaIdentityButton: some View {
        Button {
            showOwner()
        } label: {
            HStack(spacing: CrestSpacing.small) {
                artwork

                VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                    Text(verbatim: session.mediaDisplayTitle)
                        .font(CrestTypography.metadata.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: session.secondaryMetadata ?? "Media from this tab")
                        .font(CrestTypography.compactMetadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .crestHoverSurface(cornerRadius: CrestRadius.compact)
        .accessibilityLabel("Show tab playing \(session.displayTitle)")
        .help("Show Tab")
    }

    @ViewBuilder
    private var dismissButton: some View {
        if instance.availableActions.contains(.dismissMediaSession) {
            Button {
                perform(.dismissMediaSession, instance.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(
                BrowserSidebarWidgetQuietControlStyle(alignment: .topTrailing)
            )
            .accessibilityLabel("Hide Now Playing")
            .help("Hide until this tab plays again")
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkData = session.artworkData,
            let image = BrowserSidebarWidgetArtwork.image(from: artworkData)
        {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .compositingGroup()
                .clipShape(artworkShape)
                .frame(width: artworkSize, height: artworkSize)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "music.note")
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: artworkSize, height: artworkSize)
                .background(.quaternary, in: artworkShape)
                .overlay { hairline(artworkShape) }
                .accessibilityHidden(true)
        }
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: BrowserSidebarWidgetDeckStyle.artworkCornerRadius,
            style: .continuous
        )
    }

    private func hairline(_ shape: RoundedRectangle) -> some View {
        shape.stroke(
            Color.primary.opacity(
                BrowserSidebarWidgetDeckStyle.hairlineStrokeOpacity
            ),
            lineWidth: BrowserSidebarWidgetDeckStyle.cardStrokeWidth
        )
    }

    /// The owning tab sits in one corner and the volume in the other, so the
    /// transport keeps the centre of the card without floating alone in it.
    private var transportRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                cornerSlot { ownerFaviconButton }
                Spacer(minLength: 0)
                HStack(spacing: CrestSpacing.small) {
                    transportButton(
                        .previousTrack,
                        symbol: "backward.fill",
                        label: "Previous Track"
                    )
                    playbackButton
                    transportButton(
                        .nextTrack,
                        symbol: "forward.fill",
                        label: "Next Track"
                    )
                }
                Spacer(minLength: 0)
                cornerSlot { volumeButton }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                cornerSlot { ownerFaviconButton }
                Spacer(minLength: 0)
                playbackButton
                Spacer(minLength: 0)
                cornerSlot { volumeButton }
            }
            .frame(maxWidth: .infinity)

            playbackButton
                .frame(maxWidth: .infinity)
        }
    }

    private func cornerSlot(
        @ViewBuilder content: () -> some View
    ) -> some View {
        content()
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                height: BrowserSidebarWidgetDeckStyle.quietControlHitTarget
            )
    }

    private var ownerFaviconButton: some View {
        Button {
            showOwner()
        } label: {
            faviconContent
                .frame(width: faviconSize, height: faviconSize)
        }
        .buttonStyle(BrowserSidebarWidgetQuietControlStyle())
        .accessibilityLabel("Show tab playing \(session.displayTitle)")
        .help("Show Tab")
    }

    private func showOwner() {
        activate(session.owner)
    }

    @ViewBuilder
    private var faviconContent: some View {
        if let faviconData,
            let image = BrowserSidebarWidgetArtwork.image(from: faviconData)
        {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "globe")
                .font(CrestTypography.metadata)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var volumeButton: some View {
        if instance.availableActions.contains(.toggleMute) {
            Button {
                perform(.toggleMute, instance.id)
            } label: {
                Image(
                    systemName: session.isMuted
                        ? "speaker.slash.fill"
                        : "speaker.wave.2.fill"
                )
                .contentTransition(.symbolEffect(.replace))
                .animation(pressAnimation, value: session.isMuted)
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle())
            .accessibilityLabel(session.isMuted ? "Unmute" : "Mute")
            .accessibilityValue(session.isMuted ? Text("Muted") : Text("Unmuted"))
            .help(session.isMuted ? "Unmute" : "Mute")
        }
    }

    @ViewBuilder
    private var playbackButton: some View {
        let isPlaying =
            session.playbackState == .playing
            && instance.availableActions.contains(.pause)
        let action: BrowserSidebarWidgetAction = isPlaying ? .pause : .play
        if instance.availableActions.contains(action) {
            Button {
                perform(action, instance.id)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(
                        width: BrowserSidebarWidgetDeckStyle.focalControlDiameter,
                        height: BrowserSidebarWidgetDeckStyle.focalControlDiameter
                    )
                    .contentShape(.circle)
                    .animation(pressAnimation, value: isPlaying)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                height: BrowserSidebarWidgetDeckStyle.quietControlHitTarget
            )
            .contentShape(.circle)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .help(isPlaying ? "Pause" : "Play")
        }
    }

    @ViewBuilder
    private func transportButton(
        _ action: BrowserSidebarWidgetAction,
        symbol: String,
        label: LocalizedStringKey
    ) -> some View {
        if instance.availableActions.contains(action) {
            Button {
                perform(action, instance.id)
            } label: {
                Image(systemName: symbol)
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle())
            .accessibilityLabel(label)
            .help(label)
        }
    }

    private var pressAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.press,
            reduceMotion: reduceMotion
        )
    }
}

private struct BrowserSoftwareUpdateSidebarWidget: View {
    let instance: BrowserSidebarWidgetInstance
    let update: BrowserSoftwareUpdateWidgetSnapshot
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserSidebarWidgetDeckStyle.contentSpacing) {
            headerRow
            progressZone
            actions
        }
        .accessibilityLabel("Crest software update")
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: CrestSpacing.small) {
            BrowserSoftwareUpdateApplicationIcon()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                HStack(spacing: CrestSpacing.extraSmall) {
                    Text("Update Available")
                        .font(.subheadline.weight(.semibold))
                    if update.isFixture {
                        Text("TEST")
                            .font(CrestTypography.badge)
                            .padding(.horizontal, CrestSpacing.extraSmall)
                            .padding(
                                .vertical,
                                BrowserSidebarWidgetDeckStyle.badgeVerticalPadding
                            )
                            .background(
                                .orange.opacity(CrestOpacity.brandHairline),
                                in: .capsule
                            )
                            .accessibilityLabel("Test fixture")
                    }
                }
                .lineLimit(1)

                if let versionLine {
                    Text(verbatim: versionLine)
                        .font(CrestTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var progressZone: some View {
        if let progress = update.progress, isTransferring {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(CrestBrandTheme.accent)
                .accessibilityLabel(statusLabel)
        } else if isTransferring || update.phase == .checking
            || update.phase == .installing
        {
            HStack(spacing: CrestSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text(verbatim: statusLabel)
                    .font(CrestTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statusLabel)
        }

        if let message = update.message, update.phase == .failed {
            Text(verbatim: message)
                .font(CrestTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !instance.availableActions.isEmpty {
            HStack(spacing: CrestSpacing.small) {
                if instance.availableActions.contains(.dismissExactUpdate) {
                    actionButton(
                        .dismissExactUpdate,
                        label: "Skip This Version",
                        emphasis: .quiet
                    )
                }

                if instance.availableActions.contains(.installUpdate) {
                    actionButton(
                        .installUpdate,
                        label: "Download Update",
                        emphasis: .prominent
                    )
                } else if instance.availableActions.contains(.installAndRelaunch) {
                    actionButton(
                        .installAndRelaunch,
                        label: "Restart and Update",
                        emphasis: .prominent
                    )
                } else if instance.availableActions.contains(.cancelUpdate) {
                    actionButton(
                        .cancelUpdate,
                        label: "Cancel Download",
                        emphasis: .quiet
                    )
                } else if instance.availableActions.contains(.acknowledgeError) {
                    actionButton(
                        .acknowledgeError,
                        label: "Dismiss",
                        emphasis: .quiet
                    )
                }
            }
        }
    }

    private func actionButton(
        _ action: BrowserSidebarWidgetAction,
        label: LocalizedStringKey,
        emphasis: BrowserSidebarWidgetActionEmphasis
    ) -> some View {
        Button {
            perform(action, instance.id)
        } label: {
            Text(label)
        }
        .buttonStyle(BrowserSidebarWidgetActionButtonStyle(emphasis: emphasis))
        .accessibilityLabel(label)
        .help(label)
    }

    private var isTransferring: Bool {
        update.phase == .downloading || update.phase == .extracting
    }

    private var versionLine: String? {
        switch (update.version, update.build) {
        case (let version?, let build?) where version != build:
            "Version \(version) · Build \(build)"
        case (let version?, _):
            "Version \(version)"
        case (_, let build?):
            "Build \(build)"
        default:
            nil
        }
    }

    private var statusLabel: String {
        switch update.phase {
        case .checking: "Checking"
        case .available: update.isInformationOnly ? "Website release" : "Ready to download"
        case .downloading: "Downloading"
        case .extracting: "Preparing"
        case .readyToInstall: "Ready to install"
        case .installing: "Installing"
        case .failed: "Update error"
        case .unavailable: "Unavailable"
        }
    }
}

private struct BrowserSoftwareUpdateApplicationIcon: View {
    @Environment(\.browserApplicationIcon) private var applicationIcon

    var body: some View {
        (applicationIcon ?? Image(systemName: "app.fill"))
            .resizable()
            .scaledToFit()
            .frame(
                width: BrowserSidebarWidgetDeckStyle.headerTileSize,
                height: BrowserSidebarWidgetDeckStyle.headerTileSize
            )
    }
}

/// Every secondary glyph control on a card — transport, volume, and media
/// dismissal — stays visually bare until pointer hover, keyboard focus, or press.
/// The primary play/pause action owns the persistent control surface instead.
private struct BrowserSidebarWidgetQuietControlStyle: ButtonStyle {
    var alignment: Alignment = .center

    func makeBody(configuration: Configuration) -> some View {
        BrowserSidebarWidgetQuietControlSurface(
            configuration: configuration,
            alignment: alignment
        )
    }
}

private struct BrowserSidebarWidgetQuietControlSurface: View {
    let configuration: ButtonStyleConfiguration
    let alignment: Alignment

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(BrowserSidebarWidgetDeckStyle.quietControlSymbolFont)
            .foregroundStyle(foreground)
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlDiameter,
                height: BrowserSidebarWidgetDeckStyle.quietControlDiameter
            )
            .background {
                Circle()
                    .fill(emphasis)
            }
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                height: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                alignment: alignment
            )
            .contentShape(.rect)
            .crestFocusShape(Circle())
            .animation(surfaceAnimation, value: isHovering)
            .animation(surfaceAnimation, value: configuration.isPressed)
            .onHover { isHovering = $0 && isEnabled }
    }

    private var foreground: Color {
        isEnabled
            ? .primary
            : .secondary.opacity(CrestOpacity.controlDisabledForeground)
    }

    private var emphasis: Color {
        switch (configuration.isPressed && isEnabled, isHovering) {
        case (true, _):
            CrestColor.selection
        case (false, true):
            CrestColor.hover
        case (false, false):
            .clear
        }
    }

    private var surfaceAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.surface,
            reduceMotion: reduceMotion
        )
    }
}

private enum BrowserSidebarWidgetActionEmphasis {
    case prominent
    case quiet
}

/// A card-sized Crest control. `CrestButtonStyle`'s prominent capsule is built
/// for full panes; a widget card needs the same brand fill, hairline, and press
/// acknowledgement at chrome scale, on the card's own corner radius.
private struct BrowserSidebarWidgetActionButtonStyle: ButtonStyle {
    let emphasis: BrowserSidebarWidgetActionEmphasis

    func makeBody(configuration: Configuration) -> some View {
        BrowserSidebarWidgetActionSurface(
            emphasis: emphasis,
            configuration: configuration
        )
    }
}

private struct BrowserSidebarWidgetActionSurface: View {
    let emphasis: BrowserSidebarWidgetActionEmphasis
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        rendered
            .contentShape(shape)
            .crestFocusShape(shape)
            .crestPressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    @ViewBuilder
    private var rendered: some View {
        switch emphasis {
        case .prominent:
            labeled
                .browserReadableForeground(over: CrestBrandTheme.accent)
                .background(
                    CrestBrandTheme.accent.opacity(
                        configuration.isPressed
                            ? CrestButtonMetrics.pressedFillOpacity
                            : 1
                    ),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        CrestBrandPalette.ink
                            .opacity(CrestButtonMetrics.inkStrokeOpacity),
                        lineWidth: CrestButtonMetrics.strokeWidth
                    )
                }
        case .quiet:
            labeled
                .foregroundStyle(.primary)
                .background(
                    configuration.isPressed || isHovering
                        ? CrestColor.selection
                        : CrestColor.chromeSurface,
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        CrestColor.subtleBorder,
                        lineWidth: CrestButtonMetrics.strokeWidth
                    )
                }
        }
    }

    private var labeled: some View {
        configuration.label
            .font(
                CrestTypography.sans(
                    CrestButtonMetrics.standardLabelSize,
                    weight: .semibold
                )
            )
            .lineLimit(1)
            .frame(
                maxWidth: .infinity,
                minHeight: BrowserSidebarWidgetDeckStyle.actionHeight
            )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CrestRadius.control, style: .continuous)
    }
}

/// Shared bounded decode for card imagery. Ordinary page artwork keeps its
/// source pixels; only an unusually large compressed image crosses the explicit
/// decode-safety boundary and is reduced before reaching SwiftUI.
enum BrowserSidebarWidgetArtwork {
    static func image(from data: Data) -> Image? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ), let properties = properties(for: source)
        else { return nil }
        let pixelCount = properties.width.multipliedReportingOverflow(
            by: properties.height
        )
        let needsSafetyReduction =
            pixelCount.overflow
            || pixelCount.partialValue
                > BrowserMediaSessionArtworkPolicy.maximumWidgetPixelCount
            || max(properties.width, properties.height)
                > BrowserMediaSessionArtworkPolicy.maximumWidgetPixelDimension
        if needsSafetyReduction {
            guard
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize:
                            BrowserMediaSessionArtworkPolicy.maximumWidgetPixelDimension,
                        kCGImageSourceShouldCacheImmediately: true,
                    ] as CFDictionary
                )
            else { return nil }
            return Image(decorative: image, scale: 1, orientation: .up)
        }
        guard
            let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            )
        else { return nil }
        return Image(
            decorative: image,
            scale: 1,
            orientation: properties.orientation
        )
    }

    private static func properties(
        for source: CGImageSource
    ) -> (width: Int, height: Int, orientation: Image.Orientation)? {
        guard
            let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = (values[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (values[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0, height > 0
        else { return nil }
        let rawOrientation =
            (values[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        return (width, height, orientation(rawValue: rawOrientation))
    }

    private static func orientation(rawValue: UInt32) -> Image.Orientation {
        switch rawValue {
        case 2: .upMirrored
        case 3: .down
        case 4: .downMirrored
        case 5: .leftMirrored
        case 6: .right
        case 7: .rightMirrored
        case 8: .left
        default: .up
        }
    }
}
