import SwiftUI

/// A transient overlay's card and the controls that close or keep it.
///
/// One stack serves every arrangement: the arrangement decides which side of
/// the card the controls sit on and how large the card is allowed to be.
/// Everything an arrangement does not use resolves to identity, so all three
/// walk the same chain.
///
/// The card grows out of the link it came from. Where that growth is applied
/// is the one thing the arrangement changes here — the card and its controls
/// together, or the page alone — and the state hands identity to whichever
/// layer is not growing. The growth starts from the card's own frame laid
/// over the link, so the stack measures that frame inside the growth, where
/// the growth never moves it.
struct BrowserTransientCardStack<WebContent: View, LinkMenuAnchor: View>: View {
    // MARK: - Static Variables

    /// The stack as laid out, before it grows.
    private nonisolated static var layoutSpaceName: String { "crest-transient-card-stack" }

    // MARK: - Variables

    let state: BrowserTransientPresentationState
    let pageStatus: BrowserTransientPageStatus
    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let vocabulary: BrowserTransientOverlayVocabulary
    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    let actions: BrowserTransientCardActions
    @ViewBuilder let webContent: () -> WebContent
    /// The shell's control the link menu opens from, under the card.
    @ViewBuilder let linkMenuAnchor: (BrowserPeekLinkMenuPresentation) -> LinkMenuAnchor

    /// Whether the card is the preview above its link menu.
    @State private var showsLinkMenu = false
    /// Counts the times the person opened the link menu.
    @State private var linkMenuRequest = 0
    /// The card's frame in the stack as laid out.
    @State private var cardFrame: CGRect?

    var body: some View {
        VStack(
            alignment: arrangement.controlAlignment,
            spacing: arrangement.controlSpacing
        ) {
            if arrangement.placesControlsAboveCard {
                actionBar
                pageCard
            } else {
                pageCard
                actionBar
            }
        }
        // A card the person pulls carries its controls with it as it grows
        // and springs into place.
        .modifier(
            BrowserTransientMotionTransform(
                state: state.motionState, containerSize: availableSize, reduceMotion: state.reduceMotion
            )
        )
        // The page's frame is the part of the overlay the scrim dims.
        .padding(arrangement.contentInsets(safeAreaInsets: safeAreaInsets, pageInsets: state.scrimInsets))
        .modifier(BrowserTransientContentRegion(region: contentRegion))
        .coordinateSpace(.named(Self.layoutSpaceName))
        .scaleEffect(
            x: assemblyScale.width,
            y: assemblyScale.height,
            anchor: sourceTransform.anchor
        )
        .opacity(state.opacity(for: .assembly))
    }

    private var arrangement: BrowserTransientCardArrangement {
        state.arrangement
    }

    private var actionBar: some View {
        BrowserPeekActionBar(
            spaces: spaces,
            selectedSpaceID: selectedSpaceID,
            closeAccessibilityLabel: vocabulary.closeAccessibilityLabel,
            closeHelp: vocabulary.closeHelp,
            dismiss: actions.dismiss,
            openInSpace: actions.promote,
            showLinkMenu: linkMenuOpener
        )
        .modifier(BrowserTransientControlBarWidth(arrangement: arrangement))
        .opacity(showsLinkMenu ? 0 : state.controlsOpacity)
        .allowsHitTesting(state.isCardExpanded && !showsLinkMenu)
    }

    /// Opens the link menu, where the shell offers one.
    private var linkMenuOpener: (() -> Void)? {
        guard actions.linkMenu != nil else { return nil }
        return { showLinkMenu() }
    }

    /// The card shrinks to the preview above its link menu as the menu opens.
    private func showLinkMenu() {
        linkMenuRequest += 1
        withAnimation(CrestMotion.peekLinkMenu.unlessReducingMotion(state.reduceMotion)) {
            showsLinkMenu = true
        }
    }

    private func hideLinkMenu() {
        withAnimation(CrestMotion.peekLinkMenu.unlessReducingMotion(state.reduceMotion)) {
            showsLinkMenu = false
        }
    }

    private var pageCard: some View {
        BrowserTransientPageCard(
            arrangement: arrangement,
            pageStatus: pageStatus,
            vocabulary: vocabulary,
            reduceMotion: state.reduceMotion,
            reduceTransparency: state.reduceTransparency,
            restore: actions.restore,
            webContent: webContent
        )
        .modifier(BrowserTransientCardSize(size: cardSize))
        .modifier(BrowserTransientCardShare(share: state.cardShare))
        .scaleEffect(
            x: pageCardScale.width,
            y: pageCardScale.height,
            anchor: sourceTransform.anchor
        )
        .opacity(state.opacity(for: .pageCard))
        .modifier(
            BrowserPeekLinkMenuPreview(menuSize: actions.linkMenu?.size, isShowing: showsLinkMenu) { width in
                if let menu = actions.linkMenu {
                    linkMenuAnchor(
                        BrowserPeekLinkMenuPresentation(menu: menu, request: linkMenuRequest, didEnd: hideLinkMenu)
                    )
                    .frame(width: min(menu.size.width, width), height: menu.size.height)
                }
            }
        )
        // Measured outside the card's own scales, which leave its frame
        // where it was laid out. A card that follows the shared motion never
        // grows from its frame, so only one that grows is measured.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(Self.layoutSpaceName))
        } action: { frame in
            guard state.motionState == nil else { return }
            cardFrame = frame
        }
    }

    /// The region the stack is laid out inside, once the shell's own leading
    /// chrome has taken its share. `nil` wherever the overlay owns everything.
    private var contentRegion: CGRect? {
        arrangement.contentFrame(
            in: availableSize,
            reservedLeadingWidth: state.reservedLeadingWidth,
            layoutDirection: state.layoutDirection
        )
    }

    private var cardSize: CGSize? {
        arrangement.cardSize(in: contentRegion?.size ?? availableSize)
    }

    /// The transform that starts the card over the link it came from.
    private var sourceTransform: BrowserTransientSourceTransform {
        state.sourceTransform(cardFrame: cardFrame, in: availableSize)
    }

    private var assemblyScale: CGSize {
        state.scale(for: .assembly, from: sourceTransform)
    }

    private var pageCardScale: CGSize {
        state.scale(for: .pageCard, from: sourceTransform)
    }
}

// MARK: - Arrangement-shaped layout

/// The arrangement's card size, as far as the room its insets and controls
/// leave allows: a page column beside a tablet's sidebar can be narrower than
/// the card the screen would float.
private struct BrowserTransientCardSize: ViewModifier {
    let size: CGSize?

    func body(content: Content) -> some View {
        if let size {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(maxWidth: size.width, maxHeight: size.height)
        } else {
            content
        }
    }
}

/// The share of the room its controls and insets leave the card that the
/// person chose, centred in that room, so a share holds at any window size.
private struct BrowserTransientCardShare: ViewModifier {
    let share: CGFloat

    func body(content: Content) -> some View {
        ShareLayout(share: share) { content }
    }

    private struct ShareLayout: Layout {
        let share: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            subviews.first?.sizeThatFits(shared(proposal)) ?? .zero
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: shared(proposal))
        }

        private func shared(_ proposal: ProposedViewSize) -> ProposedViewSize {
            ProposedViewSize(width: proposal.width.map { $0 * share }, height: proposal.height.map { $0 * share })
        }
    }
}

private struct BrowserTransientContentRegion: ViewModifier {
    let region: CGRect?

    func body(content: Content) -> some View {
        if let region {
            content
                .frame(width: region.width, height: region.height)
                .position(x: region.midX, y: region.midY)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The card as the preview above its link menu: the same card, scaled down
/// from its top as large as leaves the menu room below it, as the system's
/// link preview sits above its menu. The menu opens from beneath the scaled
/// card, lined up with its leading edge.
private struct BrowserPeekLinkMenuPreview<Anchor: View>: ViewModifier {
    private static var largestScale: CGFloat { 0.66 }
    private static var menuGap: CGFloat { 12 }

    let menuSize: CGSize?
    let isShowing: Bool
    /// The menu's control, given the scaled card's width.
    @ViewBuilder let anchor: (CGFloat) -> Anchor

    @State private var size = CGSize.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                size = newSize
            }
            .scaleEffect(isShowing ? scale : 1, anchor: .top)
            .overlay(alignment: .top) {
                anchor(size.width * scale)
                    .frame(width: size.width * scale, alignment: .leading)
                    .offset(y: size.height * scale + Self.menuGap)
                    .allowsHitTesting(false)
            }
    }

    private var scale: CGFloat {
        guard let menuSize, size.height > 0 else { return 1 }
        return max(0, min(Self.largestScale, (size.height - menuSize.height - 2 * Self.menuGap) / size.height))
    }
}

private struct BrowserTransientControlBarWidth: ViewModifier {
    let arrangement: BrowserTransientCardArrangement

    func body(content: Content) -> some View {
        if arrangement.constrainsControlBarToMaximumWidth {
            content
                .frame(maxWidth: BrowserPeekActionBar.maximumWidth)
                .padding(arrangement.controlBarPadding)
        } else {
            content.frame(width: BrowserPeekActionBar.width)
        }
    }
}
