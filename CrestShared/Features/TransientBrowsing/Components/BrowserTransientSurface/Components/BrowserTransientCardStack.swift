import SwiftUI

/// A transient overlay's card and the controls that close or keep it.
///
/// One stack serves every arrangement: the arrangement decides which side of
/// the card the controls sit on, how large the card is allowed to be, and
/// whether a thumb on the control bar can push the whole thing away. Everything
/// an arrangement does not use resolves to identity, so all three walk the same
/// chain.
struct BrowserTransientCardStack<WebContent: View>: View {
    let state: BrowserTransientPresentationState
    let pageStatus: BrowserTransientPageStatus
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let vocabulary: BrowserTransientOverlayVocabulary
    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    let actions: BrowserTransientCardActions
    @Binding var dismissalOffset: CGFloat
    @ViewBuilder let webContent: () -> WebContent

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
        .padding(arrangement.contentInsets(safeAreaInsets: safeAreaInsets))
        .modifier(BrowserTransientDragTransform(state: state))
        .modifier(BrowserTransientContentRegion(region: contentRegion))
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
            openInSpace: actions.promote
        )
        .modifier(BrowserTransientControlBarWidth(arrangement: arrangement))
        .modifier(
            BrowserTransientDragDismissal(
                state: state,
                dismissalOffset: $dismissalOffset,
                dismiss: actions.dismiss
            )
        )
        .opacity(state.controlsOpacity)
        .allowsHitTesting(state.isCardExpanded)
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
        .scaleEffect(
            x: pageCardScale.width,
            y: pageCardScale.height,
            anchor: state.sourceTransform.anchor
        )
        .opacity(state.opacity(for: .pageCard))
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

    private var pageCardScale: CGSize {
        state.scale(for: .pageCard)
    }
}

// MARK: - Arrangement-shaped layout

private struct BrowserTransientCardSize: ViewModifier {
    let size: CGSize?

    func body(content: Content) -> some View {
        if let size {
            content.frame(width: size.width, height: size.height)
        } else {
            content
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

private struct BrowserTransientControlBarWidth: ViewModifier {
    let arrangement: BrowserTransientCardArrangement

    func body(content: Content) -> some View {
        if arrangement.constrainsControlBarToMaximumWidth {
            content
                .frame(maxWidth: BrowserPeekChromePolicy.controlBarWidth)
                .padding(arrangement.controlBarPadding)
        } else {
            content.frame(width: BrowserPeekChromePolicy.controlBarWidth)
        }
    }
}

// MARK: - Pushing the card away

/// Carries the whole assembly — card, controls, and all — as far down the
/// screen as the drag on its control bar has taken it. Identity wherever the
/// arrangement has no drag dismissal.
private struct BrowserTransientDragTransform: ViewModifier {
    let state: BrowserTransientPresentationState

    func body(content: Content) -> some View {
        if state.arrangement.allowsDragDismissal {
            content
                .offset(y: state.dragOffset)
                .scaleEffect(state.dragScale, anchor: .bottom)
        } else {
            content
        }
    }
}

/// Lets a thumb on the control bar carry the card downwards and decides, on
/// release, whether the throw was meant to close it or to be caught and settled
/// back.
///
/// The gesture sits on the bar rather than on the whole assembly because the
/// card's other half is a live web page that answers downward drags itself;
/// `BrowserTransientDragDismissalPolicy` carries that reasoning. The bar's own
/// padding is included in the grab area, so the strip beneath the card is a
/// target of its full width rather than only where a control is drawn.
private struct BrowserTransientDragDismissal: ViewModifier {
    let state: BrowserTransientPresentationState
    @Binding var dismissalOffset: CGFloat
    let dismiss: () -> Void
    @State private var isCarryingCard = false

    func body(content: Content) -> some View {
        if state.arrangement.allowsDragDismissal {
            content
                .contentShape(.rect)
                .simultaneousGesture(dismissGesture)
        } else {
            content
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(
            minimumDistance: BrowserTransientDragDismissalPolicy
                .minimumDragDistance
        )
        .onChanged { value in
            guard
                BrowserTransientDragDismissalPolicy.carriesCard(
                    translation: value.translation
                )
            else { return }
            isCarryingCard = true
            dismissalOffset =
                BrowserTransientDragDismissalPolicy.dismissalOffset(
                    for: value.translation
                )
        }
        .onEnded { value in
            let closesCard = BrowserTransientDragDismissalPolicy.closesCard(
                predictedEndTranslation: value.predictedEndTranslation,
                wasCarryingCard: isCarryingCard
            )
            isCarryingCard = false
            guard !closesCard else {
                dismiss()
                return
            }
            withAnimation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.peekDragSettlement,
                    reduceMotion: state.reduceMotion
                )
            ) {
                dismissalOffset = 0
            }
        }
    }
}
