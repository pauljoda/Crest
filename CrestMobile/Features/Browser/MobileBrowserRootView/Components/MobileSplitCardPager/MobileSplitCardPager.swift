import SwiftUI

/// The iPhone's answer to columns: the cards of a split laid out in a row, one
/// at a time, paged by the toolbar swipe.
///
/// Built on the same skeleton as `BrowserSpacePager` — a lazy horizontal stack
/// of container-width cells, view-aligned one at a time, with a two-way
/// `scrollPosition` binding — and disabled for direct dragging, which is the one
/// place the two part company. `MobileSplitCardPagerPolicy.allowsDirectDrag`
/// carries the reasoning.
///
/// The two-way sync still earns its keep with paging programmatic: focus moves
/// from the sidebar, a hardware keyboard, and sync as well as from the swipe,
/// and every one of those routes has to bring the carousel with it.
struct MobileSplitCardPager: View {
    let members: [BrowserTab]
    let space: BrowserSpace
    let focusedTabID: TabID
    let pages: MobileBrowserPageStore
    let viewport: MobileBrowserPageViewport
    let selectTab: (TabID) -> Void
    let prepareMember: (TabID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleTabID: TabID?
    @State private var recenterRevision: UInt = 0

    init(
        members: [BrowserTab],
        space: BrowserSpace,
        focusedTabID: TabID,
        pages: MobileBrowserPageStore,
        viewport: MobileBrowserPageViewport,
        selectTab: @escaping (TabID) -> Void,
        prepareMember: @escaping (TabID) -> Void
    ) {
        self.members = members
        self.space = space
        self.focusedTabID = focusedTabID
        self.pages = pages
        self.viewport = viewport
        self.selectTab = selectTab
        self.prepareMember = prepareMember
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
                showsIndicators: MobileSplitCardPagerPolicy.showsScrollIndicators
            ) {
                LazyHStack(spacing: 0) {
                    ForEach(members) { member in
                        MobileSplitCardPage(
                            member: member,
                            space: space,
                            pages: pages,
                            viewport: viewport,
                            prepareMember: prepareMember
                        )
                        .containerRelativeFrame(.horizontal)
                        .id(member.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(
                MobileSplitCardPagerPolicy.scrollIndicatorVisibility,
                axes: .horizontal
            )
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $visibleTabID, anchor: .center)
            .scrollDisabled(!MobileSplitCardPagerPolicy.allowsDirectDrag)
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
                    BrowserVisualAccessibilityPolicy.animation(
                        CrestMotion.spaceSwipe,
                        reduceMotion: reduceMotion
                    )
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

    private func focusAdjacentCard(_ direction: BrowserSpaceSwipeDirection) {
        guard
            let tabID = MobileSplitCardPagerPolicy.adjacentMember(
                of: focusedTabID,
                in: members.map(\.id),
                direction: direction
            )
        else { return }
        selectTab(tabID)
    }
}

#Preview("Split Card Pager", traits: .fixedLayout(width: 390, height: 640)) {
    @Previewable @State var focusedTabID = BrowserSplitViewPreviewFixture.middleTabID
    let fixture = MobileBrowserPreviewFixture()

    MobileSplitCardPager(
        members: BrowserSplitViewPreviewFixture.members,
        space: fixture.space,
        focusedTabID: focusedTabID,
        pages: fixture.pages,
        viewport: .inline,
        selectTab: { focusedTabID = $0 },
        prepareMember: { _ in }
    )
    .background(.quaternary)
}
