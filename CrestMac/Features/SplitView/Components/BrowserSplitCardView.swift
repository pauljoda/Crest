import SwiftUI

/// One card of a macOS split: the per-card twin of `BrowserDetailView`.
///
/// Both resolve a page and a presentation and then hand the same
/// `BrowserDetailContent` the result, which is deliberate — the find bar, the
/// navigation-failure overlay, the credential chrome, and the developer toolbar
/// all live on `BrowserPage`, so a card that renders the same content view gets
/// every one of them for its own page with nothing per-card to maintain.
///
/// The difference is which tab it speaks for. `BrowserDetailView` speaks for the
/// selected tab; a card speaks for its own member, focused or not, and resolves
/// its page through the assignment-checked accessor so a Space switch mid-frame
/// can never bind a page belonging to another Space or profile.
///
/// Three things ride along that the single-page path has no need for:
///
/// - **Hover tracking**, as an AppKit tracking area rather than `.onHover`, which
///   is unreliable over live web content. Whether the pointer in the card is
///   worth a focus change is `focusesOnHover`'s answer, evaluated as the pointer
///   arrives and moves so nothing here has to observe the preference or the
///   address field.
/// - **Frame registration**, twice over. The surface's own registry, in its named
///   space, is how a single mouse-down monitor turns a point into a card — a tap
///   gesture cannot replace it, because web content consumes the clicks that
///   matter. The reorder state's registry, in the global space, is how a drag
///   arriving from the sidebar knows which cards it is between.
///
/// Every card's page, focused or not, reports its navigations to the core,
/// which keeps its tab row and history current.
struct BrowserSplitCardView: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let tab: TabStateModel
    let space: SpaceModel
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let tabPromotionNamespace: Namespace.ID
    let startPageFocusRequest: Int
    let isCommandPalettePresented: Bool
    /// The window's commands, for a Start Page card's palette.
    let commands: BrowserCommandPaletteCommandRegistry
    /// Where this card records its bounds for the surface's click monitor.
    let cardFrames: BrowserSplitCardFrameRegistry
    /// Asked with the pointer's location in the card-frame space as it enters
    /// the card or moves off chrome drawn over it, never during layout, so the
    /// guards it consults are read fresh and observing them costs no re-render
    /// here.
    let focusesOnHover: @MainActor @Sendable (CGPoint) -> Bool
    /// Whether chrome drawn over the card, such as the floating sidebar or a
    /// Peek, covers a location in the card-frame space.
    let isCoveredByChrome: @MainActor @Sendable (CGPoint) -> Bool
    /// This card's request to become the focused one.
    let onFocusRequest: @MainActor @Sendable () -> Void
    /// The window's part of the bar this card carries while the address bar
    /// is on top, or nil while it is in the sidebar.
    var cardBar: BrowserPageCardBarContext? = nil
    /// Whether this card is the focused one, which its bar draws at full
    /// strength.
    var isFocused = false
    /// Whether this card comes first in reading order.
    var isLeadingCard = false

    private var isSelectedSpace: Bool {
        browser.selectedSpaceID == space.id && !spaceAccess.isLocked(space)
    }

    var body: some View {
        let page = presentedPage
        VStack(spacing: 0) {
            if let cardBar {
                BrowserPageCardBar(
                    page: page, tab: tab, space: space, browser: browser, pages: pages, context: cardBar,
                    isFocused: isFocused, isLeadingCard: isLeadingCard
                )
                .transition(BrowserPageCardBar.transition)
            }
            BrowserDetailContent(
                page: page,
                tab: tab,
                space: space,
                pagePresentation: .of(tab.surface, page: page),
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                tabPromotionNamespace: tabPromotionNamespace,
                startPageFocusRequest: startPageFocusRequest,
                isCommandPalettePresented: isCommandPalettePresented,
                commands: commands
            )
        }
        .overlay {
            BrowserSplitCardHoverTracker { location in
                cardPoint(location).map(isCoveredByChrome) ?? false
            } onPointerInside: { location in
                guard isSelectedSpace, let point = cardPoint(location), focusesOnHover(point) else { return }
                onFocusRequest()
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: BrowserSplitCardFrameRegistry.coordinateSpace)
        } action: { frame in
            cardFrames.register(frame, for: tab.id)
        }
        // A lone card shows another tab where it stands, at the same frame,
        // so its entry follows the tab rather than waiting for the geometry.
        .onChange(of: tab.id) { oldTabID, newTabID in
            cardFrames.moveFrame(from: oldTabID, to: newTabID)
        }
        .onDisappear {
            cardFrames.removeFrame(for: tab.id)
        }
        .browserSplitDropCardFrame(
            tabID: isSelectedSpace ? tab.id : nil,
            assignment: isSelectedSpace ? BrowserSpaceRuntimeAssignment(space: space) : nil,
            state: sidebarInteraction.sidebarReorderState
        )
    }

    private var presentedPage: BrowserPage? {
        pages.surfacePage(for: tab.id, in: space, accessController: spaceAccess)
    }

    /// A location in the card's bounds, in the card-frame space, once the
    /// card's frame is known.
    private func cardPoint(_ location: CGPoint) -> CGPoint? {
        cardFrames.frame(for: tab.id).map { CGPoint(x: $0.minX + location.x, y: $0.minY + location.y) }
    }
}
