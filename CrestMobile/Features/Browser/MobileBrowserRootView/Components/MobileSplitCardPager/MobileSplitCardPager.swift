import SwiftUI

/// The iPhone's answer to columns: the cards of a split laid out in a row, one
/// at a time, paged by the toolbar swipe.
///
/// Built on the same skeleton as `BrowserSpacePager` — a lazy horizontal stack
/// of container-width cells, view-aligned one at a time, with a two-way
/// `scrollPosition` binding — and disabled for direct dragging, which is the one
/// place the two part company. `allowsDirectDrag` carries the reasoning.
///
/// The two-way sync still earns its keep with paging programmatic: focus moves
/// from the sidebar, a hardware keyboard, and sync as well as from the swipe,
/// and every one of those routes has to bring the carousel with it.
struct MobileSplitCardPager: View {
    // MARK: - Static Variables

    /// Whether a finger on the page may page the carousel.
    ///
    /// `false` for 0.4, and the pager is `scrollDisabled` because of it. A
    /// horizontal `ScrollView` wrapped around live `WKWebView`s competes with
    /// every page's own horizontal pan — carousels, maps, code blocks, and the
    /// back/forward edge swipe — and the loser of that arbitration
    /// is whichever one the person actually meant. Paging is therefore
    /// programmatic: the toolbar swipe commits a selection and the pager
    /// animates to it. Direct content-drag paging is a post-0.4 gesture spike.
    static let allowsDirectDrag = false

    static let showsScrollIndicators = false

    static var scrollIndicatorVisibility: ScrollIndicatorVisibility { .never }

    // MARK: - Variables

    let members: [TabStateModel]
    let space: SpaceModel
    let focusedTabID: UUID
    let pages: MobileBrowserPageStore
    let viewport: MobileBrowserPageViewport
    let selectTab: (UUID) -> Void
    let prepareMember: (UUID) -> Void
    let handleInteraction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleTabID: UUID?
    @State private var recenterRevision: UInt = 0

    init(
        members: [TabStateModel],
        space: SpaceModel,
        focusedTabID: UUID,
        pages: MobileBrowserPageStore,
        viewport: MobileBrowserPageViewport,
        selectTab: @escaping (UUID) -> Void,
        prepareMember: @escaping (UUID) -> Void,
        handleInteraction: @escaping () -> Void
    ) {
        self.members = members
        self.space = space
        self.focusedTabID = focusedTabID
        self.pages = pages
        self.viewport = viewport
        self.selectTab = selectTab
        self.prepareMember = prepareMember
        self.handleInteraction = handleInteraction
        _visibleTabID = State(initialValue: focusedTabID)
        assert(
            Set(members.map(\.id)).count == members.count,
            """
            Split members must be unique. Two cells for one member would hand \
            the same live web view to two hosts, and the second attach silently \
            takes it away from the first.
            """
        )
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(
                .horizontal,
                showsIndicators: Self.showsScrollIndicators
            ) {
                LazyHStack(spacing: 0) {
                    ForEach(members) { member in
                        MobileSplitCardPage(
                            member: member,
                            space: space,
                            pages: pages,
                            viewport: viewport,
                            prepareMember: prepareMember,
                            handleInteraction: handleInteraction
                        )
                        .containerRelativeFrame(.horizontal)
                        .id(member.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(
                Self.scrollIndicatorVisibility,
                axes: .horizontal
            )
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $visibleTabID, anchor: .center)
            .scrollDisabled(!Self.allowsDirectDrag)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Split View Cards")
            .accessibilityIdentifier("split-card-pager")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    focusAdjacentCard(.next)
                case .decrement:
                    focusAdjacentCard(.previous)
                @unknown default:
                    break
                }
            }
            .accessibilityAction(named: "Previous Split View Card") {
                focusAdjacentCard(.previous)
            }
            .accessibilityAction(named: "Next Split View Card") {
                focusAdjacentCard(.next)
            }
            .onChange(of: visibleTabID) { _, tabID in
                // Guarded on membership as well as on change: a member closed
                // mid-animation leaves the scroll view resting on a card the
                // session no longer has, and committing that would select a tab
                // that is gone.
                guard let tabID,
                    tabID != focusedTabID,
                    members.contains(where: { $0.id == tabID })
                else { return }
                selectTab(tabID)
            }
            .onChange(of: focusedTabID, initial: true) { _, tabID in
                recenterRevision &+= 1
                guard members.contains(where: { $0.id == tabID }),
                    visibleTabID != tabID
                else { return }
                withAnimation(
                    CrestMotion.spaceSwipe.unlessReducingMotion(reduceMotion)
                ) {
                    visibleTabID = tabID
                }
            }
            .onChange(of: members.map(\.id)) { _, _ in
                recenter(using: scrollProxy)
            }
            .onScrollPhaseChange { _, phase in
                // A settled scroll that ended somewhere other than the focused
                // card means an animation was interrupted; the selection is the
                // truth, so the carousel goes back to it.
                guard !phase.isScrolling,
                    let visibleTabID,
                    visibleTabID != focusedTabID,
                    members.contains(where: { $0.id == visibleTabID })
                else { return }
                selectTab(visibleTabID)
            }
        }
    }

    /// Puts the carousel back on the focused card without animating.
    ///
    /// Membership changed under the scroll view, so there is no motion worth
    /// showing between an arrangement that no longer exists and the one that
    /// replaced it. The work is deferred one turn because the new run has not
    /// been laid out yet, and the request guards against a second change
    /// arriving before that turn comes.
    private func recenter(using scrollProxy: ScrollViewProxy) {
        recenterRevision &+= 1
        guard members.contains(where: { $0.id == focusedTabID }) else { return }
        let request = MobileSplitCardPagerRecenterRequest(
            revision: recenterRevision,
            tabID: focusedTabID
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visibleTabID = request.tabID
        }
        DispatchQueue.main.async {
            guard
                request.isCurrent(
                    revision: recenterRevision,
                    focusedTabID: focusedTabID
                )
            else { return }
            var settledTransaction = Transaction()
            settledTransaction.disablesAnimations = true
            withTransaction(settledTransaction) {
                visibleTabID = request.tabID
                scrollProxy.scrollTo(request.tabID, anchor: .center)
            }
        }
    }

    /// Whether a presented run is long enough to page at all. A run of one is a
    /// plain tab and renders through the ordinary single-page path.
    nonisolated static func presents(memberCount: Int) -> Bool {
        memberCount >= SplitGroupState.minimumShownMembers
    }

    /// The card one step from `tabID`, clamped at both ends.
    ///
    /// Deliberately not wrapping. A swipe is a spatial gesture — the cards sit in
    /// a row — so running off the end and reappearing at the other would read as
    /// the carousel losing its place. The keyboard's focus-cycling commands do
    /// wrap, because a repeated chord is a cycle rather than a direction.
    nonisolated static func adjacentMember(
        of tabID: UUID,
        in members: [UUID],
        direction: BrowserSpaceSwipeDirection
    ) -> UUID? {
        guard let index = members.firstIndex(of: tabID) else { return nil }
        let target = direction == .next ? index + 1 : index - 1
        guard members.indices.contains(target) else { return nil }
        return members[target]
    }

    private func focusAdjacentCard(_ direction: BrowserSpaceSwipeDirection) {
        guard
            let tabID = Self.adjacentMember(
                of: focusedTabID,
                in: members.map(\.id),
                direction: direction
            )
        else { return }
        selectTab(tabID)
    }
}
