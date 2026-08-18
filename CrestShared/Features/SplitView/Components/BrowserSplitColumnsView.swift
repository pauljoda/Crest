import SwiftUI

/// Crest's split-view layout manager: an ordered row of cards, the gaps between
/// them, and the dividers that live in those gaps.
///
/// The view owns geometry and nothing else. Widths come from
/// `BrowserSplitColumnLayout`, membership comes from the session, and what a
/// card actually shows comes from `content` — which is what lets macOS hand it
/// live web views and iPadOS hand it its own hosts without either platform
/// re-deriving a column. The single-card case is deliberately not special: a
/// window presenting one tab is a one-column split with no dividers and no
/// focus ring.
///
/// Three conventions the callers depend on:
///
/// - The outer page insets are applied here, once, so a card can wrap itself in
///   `BrowserRootContentSurface` with zero insets of its own and the row still
///   reads as the single evenly inset page surface it replaces. Inter-card
///   breathing room is the gap, never a card's padding.
/// - A drag's drop placeholder is a column, not an ornament. Members and
///   placeholder are one `BrowserSplitColumnSlot` list, so the same `HStack`,
///   the same gap, the same surface, and the same width arithmetic serve both,
///   and the slot under the pointer is already the exact width and position the
///   card that lands in it will have.
/// - `ForEach` identity is the slot's `TabID` — `nil` for the placeholder — so a
///   focus change, a resize, a neighbour arriving, or the drop itself updates a
///   card's host rather than remounting it. A remounted host would hand a live
///   `WKWebView` to a second superview.
/// - A card carried out of the row on the pointer is *not* a fourth kind of
///   slot. It is still its own member, at whichever position the gap has reached,
///   and it simply stops drawing. That is what lets a whole reorder happen with
///   the lifted card's host, and the live web view inside it, untouched — and it
///   is why the row is already in the order the drop commits before the session
///   has heard about it.
///
/// The row is also the coordinate space every divider drag is measured in. It
/// declares `BrowserSplitResizeSpace` here, once, because it is the last thing
/// in the hierarchy that stays put while fractions change: the handles below it
/// are positioned from those fractions and travel with the boundaries they move.
/// A resize also writes without an implicit animation — the settle animation
/// below belongs to a column opening or closing, not to pointer tracking, which
/// has to land on the frame it was measured for.
struct BrowserSplitColumnsView<Content: View>: View {
    /// The presented cards, in session member order.
    let members: [BrowserTab]
    /// The one card browser chrome speaks for.
    let focusedTabID: TabID?
    /// The page insets the whole row sits inside, leading-zeroed when the row
    /// adjoins a docked sidebar.
    let frameInsets: EdgeInsets
    /// The Space accent the focus ring is drawn in.
    let accent: Color
    /// Where a drag in flight would insert a card, in `0...members.count`.
    /// Anything else — including `nil` — lays the row out with no placeholder.
    let placeholderIndex: Int?
    /// The member currently carried on the pointer, if any. `members` already
    /// holds it at the slot the gap has reached; this is what makes that slot
    /// read as the gap — an empty column of exactly the size and position the
    /// card will drop back into.
    let liftedTabID: TabID?
    @Binding var widthTransaction: BrowserSplitWidthTransaction
    /// The fractions a completed divider drag settled on, worth persisting.
    let onResizeCommit: ([Double]) -> Void
    /// A request to make one card the focused one.
    let onFocus: (TabID) -> Void
    let usesTransparentInnerSurface: (BrowserTab) -> Bool
    @ViewBuilder let content: (BrowserTab, Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            columns(containerWidth: proxy.size.width)
        }
        .padding(frameInsets)
        // Keyed on the slot list rather than on membership alone, so the drop
        // column opening, moving between gaps, and closing again all settle
        // with the same motion a member joining or leaving does.
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.collection,
                reduceMotion: reduceMotion
            ),
            value: slots.map(\.id)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Split View Columns")
    }

    private func columns(containerWidth: CGFloat) -> some View {
        let widths = slotWidths(containerWidth: containerWidth)
        return ZStack(alignment: .leading) {
            cardRow(widths: widths)
            dividers(cardWidths: widths, containerWidth: containerWidth)
        }
        .coordinateSpace(BrowserSplitResizeSpace.coordinateSpace)
    }

    private func cardRow(widths: [CGFloat]) -> some View {
        HStack(spacing: BrowserSplitLayoutMetrics.interCardGap) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { column in
                columnSlot(
                    column.element,
                    width: width(at: column.offset, in: widths)
                )
                .zIndex(cardZIndex(for: column.element))
            }
        }
    }

    /// One column: the shared page surface, at the width the row gave it, with
    /// the adornments only a real member carries.
    @ViewBuilder
    private func columnSlot(
        _ slot: BrowserSplitColumnSlot,
        width: CGFloat
    ) -> some View {
        let surface = slotSurface(slot).frame(width: width)

        switch slot {
        case .member(let member) where member.id == liftedTabID:
            // The gap. It wears none of the adornments of a card that is
            // present — no focus ring around an empty column, no invitation to
            // focus a card nobody can see — and it leaves the accessibility tree
            // for as long as the carry lasts. The card is still mounted
            // underneath, keeping its host and its live page, but a card
            // somebody is holding on the pointer is not one of the cards on
            // show, and the gesture that put it there is a pointer's alone.
            surface.accessibilityHidden(true)
        case .member(let member):
            surface
                .overlay {
                    if members.count > 1 {
                        BrowserSplitCardFocusIndicator(
                            isFocused: member.id == focusedTabID,
                            accent: accent
                        )
                    }
                }
                .accessibilityAction(named: "Focus This Split View Card") {
                    onFocus(member.id)
                }
        case .placeholder:
            surface
                // The drag that summoned it owns every event, so the column
                // neither hit-tests nor announces itself twice.
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Add to Split View")
        }
    }

    /// The page surface every column wears, member or not. A drop placeholder
    /// that borrowed a border of its own would read as a different kind of thing
    /// from the card about to replace it; this is that card's surface, already
    /// drawn.
    private func slotSurface(_ slot: BrowserSplitColumnSlot) -> some View {
        let isGap = slot.member.map { $0.id == liftedTabID } ?? false
        return BrowserRootContentSurface(
            cornerRadius: BrowserChromeLayout.pageCornerRadius,
            seamWidth: BrowserChromeLayout.pageBrandSeamWidth,
            frameInsets: EdgeInsets(),
            usesTransparentInnerSurface: isGap
                // An empty column is not a page that draws its own atmosphere,
                // whether it is empty because nothing has arrived yet or because
                // its card is out on the pointer.
                ? false
                : slot.member.map(usesTransparentInnerSurface) ?? false
        ) {
            switch slot {
            case .member(let member):
                // Transparent rather than removed, and deliberately not
                // `hidden()`. The card has to keep its host — a remount would
                // hand a live `WKWebView` to a second superview — and a web view
                // AppKit considers hidden reports itself hidden to the page as
                // well, which would pause its media and fire a visibility change
                // every time somebody rearranged a column.
                content(member, member.id == focusedTabID)
                    .opacity(isGap ? 0 : 1)
            case .placeholder:
                BrowserSplitPlaceholderCard()
            }
        }
    }

    private func dividers(
        cardWidths: [CGFloat],
        containerWidth: CGFloat
    ) -> some View {
        ForEach(dividerIndices, id: \.self) { index in
            BrowserSplitCardResizeHandle(
                dividerIndex: index,
                resize: { delta in
                    resize(dividerIndex: index, delta: delta, containerWidth: containerWidth)
                },
                commit: {
                    guard let committed = widthTransaction.commit() else { return }
                    onResizeCommit(committed)
                }
            )
            .offset(
                x: BrowserChromeDirectionPolicy.leadingOffset(
                    BrowserSplitColumnLayout.dividerLeadingDistance(
                        after: index,
                        cardWidths: cardWidths
                    ),
                    layoutDirection: layoutDirection
                )
            )
        }
    }

    /// Moves one boundary to where the pointer has taken it, this frame.
    ///
    /// Explicitly unanimated. The row carries a settle animation for slots
    /// arriving and leaving, and while that animation is keyed on the slot list
    /// rather than on widths, an inherited transaction from anywhere above would
    /// interpolate the boundary toward a pointer that has already moved on. A
    /// drag has to land on the geometry it was measured against.
    private func resize(dividerIndex: Int, delta: CGFloat, containerWidth: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            widthTransaction.resize(
                dividerIndex: dividerIndex,
                delta: delta,
                containerWidth: containerWidth
            )
        }
    }

    /// The gaps that carry a divider: one after every card but the last.
    ///
    /// A gesture in flight has none. The pointer already belongs to that gesture
    /// — a drag from the sidebar, or a card being carried between its neighbours
    /// — and a handle offered under a pointer that is busy is a resize nobody can
    /// start. The drop placeholder has moved every boundary as well.
    private var dividerIndices: [Int] {
        guard resolvedPlaceholderIndex == nil,
            liftedTabID == nil,
            members.count > 1
        else { return [] }
        return Array(0..<(members.count - 1))
    }

    private var slots: [BrowserSplitColumnSlot] {
        BrowserSplitColumnSlot.slots(
            members: members,
            placeholderIndex: placeholderIndex
        )
    }

    /// One width per slot, placeholder included.
    ///
    /// A drag asks the same arithmetic the drop will: the fractions the joining
    /// card produces, spread across the same container. Nothing about the row
    /// changes on release except which view occupies the column.
    private func slotWidths(containerWidth: CGFloat) -> [CGFloat] {
        BrowserSplitColumnLayout.widths(
            containerWidth: containerWidth,
            fractions: slotFractions
        )
    }

    private var slotFractions: [Double] {
        guard let placeholderIndex = resolvedPlaceholderIndex else {
            return resolvedFractions
        }
        return BrowserSplitColumnLayout.fractionsInserting(
            at: placeholderIndex,
            into: resolvedFractions
        )
    }

    /// The live fractions, or equal columns while the transaction is still a
    /// membership behind. Seeding runs on a change the row has already drawn.
    private var resolvedFractions: [Double] {
        BrowserSplitLayoutSeedPolicy.fractions(
            persisted: widthTransaction.fractions,
            memberCount: members.count
        )
    }

    private var resolvedPlaceholderIndex: Int? {
        guard let placeholderIndex,
            placeholderIndex >= 0,
            placeholderIndex <= members.count
        else { return nil }
        return placeholderIndex
    }

    private func width(at index: Int, in widths: [CGFloat]) -> CGFloat {
        widths.indices.contains(index) ? widths[index] : 0
    }

    private func cardZIndex(for slot: BrowserSplitColumnSlot) -> Double {
        guard case .member(let member) = slot,
            member.id == focusedTabID
        else { return BrowserSplitLayoutMetrics.restingCardZIndex }
        return BrowserSplitLayoutMetrics.focusedCardZIndex
    }
}
