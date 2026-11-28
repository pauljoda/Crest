import SwiftUI

/// The compact shell's scrolling chrome around the shared tab list.
///
/// What belongs to this shell rather than to the list is the prepositioning: the
/// page a row opens grows out of that row in place, so the row has to be on
/// screen with a real resting frame before the morph starts. The lists are lazy,
/// and scrolling to the shown tab's row by its identity makes that row before
/// the morph reads its frame.
///
/// The list's sections are stacked as they are: each makes its own tab rows
/// lazily, and a lazy stack around them would size every section from an
/// estimate, which with the section's own lazy rows inside could keep the
/// sidebar's layout from ever settling. The stack keeps each section at its
/// own height, so the room left below them goes to the empty area and never to
/// a row that can stretch.
struct MobileBrowserSpaceTabListScroll<Content: View>: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let context: BrowserSidebarListContext
    let compactPageIsFullyPresented: Bool
    let openNewTab: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var scrollRegionID = UUID()
    /// Where the list sits and how far it has scrolled. Both change on every
    /// scroll frame and only the reorder state reads them, so they are kept by
    /// reference and never rebuild this view while the list moves.
    @State private var scrollOrigin = MobileSidebarScrollOrigin()

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        content()
                    }
                    .sidebarScrollContent()
                    .padding(.bottom, CrestSpacing.small)
                    .sidebarRemainderBackground(viewportHeight: geometry.size.height) {
                        Color.clear
                            .contentShape(.rect)
                            .modifier(
                                BrowserSidebarEmptySpaceNewTabGesture(
                                    tabActions: context.tabActions,
                                    openNewTab: openNewTab
                                )
                            )
                            .accessibilityHidden(true)
                    }
                    .coordinateSpace(BrowserSidebarVisibleBand.contentSpace)
                    .environment(\.browserSidebarScrollContentSpace, BrowserSidebarVisibleBand.contentSpace)
                }
                .environment(\.browserSidebarScrollRegionID, scrollRegionID)
                .onScrollGeometryChange(for: CGRect.self) {
                    $0.visibleRect
                } action: { _, rect in
                    scrollOrigin.visibleOrigin = rect.origin
                    scrollOrigin.publish(for: scrollRegionID, to: sidebarInteraction.sidebarReorderState)
                }
                .background {
                    Color.clear
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
                        } action: { frame in
                            scrollOrigin.regionFrame = frame
                            sidebarInteraction.sidebarReorderState.register(
                                scrollRegionFrame: frame,
                                for: scrollRegionID
                            )
                            scrollOrigin.publish(for: scrollRegionID, to: sidebarInteraction.sidebarReorderState)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .onDisappear {
                    sidebarInteraction.sidebarReorderState.removeScrollRegion(for: scrollRegionID)
                }
                // Named before the scroll affordance, so its "Show more tabs"
                // button keeps its own label and identifier.
                .accessibilityLabel("Saved and current tabs")
                .accessibilityIdentifier(
                    BrowserSpaceAccessibilityID.tabs(context.space.id)
                )
                .modifier(SidebarScrollAffordance(isDragging: sidebarInteraction.sidebarReorderState.isDragging))
                .scrollClipDisabled(
                    !BrowserSidebarReorderVisuals.clipsScrollableRegion(
                        clipsWhenIdle: BrowserSidebarReorderVisuals.clipsScrollableRegionWhenIdle,
                        isDragging: sidebarInteraction.sidebarReorderState.isDragging
                    )
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        BrowserAddressFocusDismissal.dismiss()
                    }
                )
                .onChange(of: selectedPromotionTarget) { previous, current in
                    guard compactPageIsFullyPresented, let current, previous != current
                    else { return }

                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(current.tabID, anchor: .center)
                    }
                }
            }
        }
    }

    /// Where the page the window shows would grow out of, which reads only the
    /// Space's shown tab, not any list.
    private var selectedPromotionTarget: MobileTabPromotionTarget? {
        let spaceID = context.space.id
        guard let tabID = context.window.shownTabs.first(where: { $0.spaceID == spaceID })?.tabID,
            let tab = context.space.shownTab(tabID)
        else { return nil }
        return MobileTabPromotionTarget(shownTab: tab)
    }
}

/// The list's frame in the window and its live scroll offset, which the
/// reorder state reads to hit-test rows frozen at a lift. A plain reference,
/// so the scroll frames that change it never invalidate a view.
@MainActor
private final class MobileSidebarScrollOrigin {
    // MARK: - Variables

    var regionFrame = CGRect.zero
    var visibleOrigin = CGPoint.zero
    private var lastContentOrigin: CGPoint?

    // MARK: - Actions - Publishing

    /// Forwards live scroll-origin changes and lift-time scroll movement to
    /// the reorder state so frozen-origin hit testing stays aligned while
    /// scrolling during a lift.
    func publish(for regionID: UUID, to reorderState: BrowserSidebarReorderState) {
        guard !regionFrame.isEmpty else { return }
        let origin = CGPoint(x: regionFrame.minX - visibleOrigin.x, y: regionFrame.minY - visibleOrigin.y)
        reorderState.register(scrollContentOrigin: origin, for: regionID)
        if let previous = lastContentOrigin, reorderState.isDragging {
            let visualOffset = origin.y - previous.y
            if visualOffset != 0 {
                reorderState.scrollableContentDidMove(in: regionID, by: visualOffset)
            }
        }
        lastContentOrigin = origin
    }
}
