import SwiftUI

/// A Space's pinned extension tiles in the sidebar, in the order the person
/// left them. Where the strip can be reordered, a tile dragged along it lifts
/// as a sidebar row does: the window draws it at the pointer, the others close
/// up around the gap where it would land, and letting go settles it there.
struct BrowserPinnedExtensionActionList: View {
    // MARK: - Types

    /// The Space whose strip this is, and how its tiles move.
    struct Reordering {
        let space: BrowserSpaceIdentity
        /// Moves a tile to just before another, or to the end before none.
        let move: (_ extensionID: String, _ beforeID: String?) -> Void
    }

    // MARK: - Variables

    let actions: [BrowserExtensionActionPresentation]
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    var prepare: (BrowserExtensionActionPresentation) -> Void = { _ in }
    var presentMenu:
        (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) ->
            Void = { _, _ in }
    /// How the tiles move, or nil for a strip that keeps its order.
    var reordering: Reordering?
    /// The Space whose strip this is, whether or not it can be reordered.
    var spaceID: UUID?

    @Environment(BrowserExtensionTileLiftState.self) private var tileLift: BrowserExtensionTileLiftState?
    @Environment(\.sidebarSpaceIsSelected) private var isSelectedSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the row's first slot is in the window.
    @State private var rowOrigin = CGPoint.zero

    var body: some View {
        let ordered = orderedActions
        let layout = slotLayout(for: ordered.map(\.id))
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                layout {
                    ForEach(ordered) { action in
                        BrowserPinnedExtensionActionButton(
                            action: action,
                            perform: { perform(action, $0) },
                            prepare: { prepare(action) },
                            presentMenu: { presentMenu(action, $0) }
                        )
                        .opacity(hidesTile(action.id) ? 0 : 1)
                        .modifier(liftSource(for: action, order: ordered.map(\.id)))
                    }
                }
                .onGeometryChange(for: CGPoint.self) {
                    $0.frame(in: BrowserSidebarReorderSpace.globalSpace).origin
                } action: {
                    rowOrigin = $0
                }
                .animation(CrestMotion.dragSource.unlessReducingMotion(reduceMotion), value: layout.slots)
                // The slots run left to right in every language, as the drag
                // reads them from the pointer's place in the window.
                .environment(\.layoutDirection, .leftToRight)
                // Size the scroll content in both axes so the buttons stay
                // centered when the viewport is laid out again.
                .frame(
                    minWidth: proxy.size.width,
                    minHeight: proxy.size.height
                )
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(tileLift?.isCarrying == true)
        }
        .onChange(of: actions.map(\.id), initial: true) { _, ids in
            if let reordering { tileLift?.engineReported(ids, profileID: reordering.space.profileID) }
            if let spaceID { tileLift?.stripChanged(to: ids, in: spaceID, isReorderable: isReorderable) }
        }
        .onChange(of: isReorderable) { _, isReorderable in
            guard let spaceID else { return }
            tileLift?.stripChanged(to: actions.map(\.id), in: spaceID, isReorderable: isReorderable)
        }
        .onDisappear {
            guard let reordering, tileLift?.lift?.spaceID == reordering.space.id else { return }
            tileLift?.abandon()
        }
    }

    // MARK: - Actions - Reordering

    /// The tiles in the order the strip shows: the engine's, or the one a
    /// release made while the engine has yet to report it.
    private var orderedActions: [BrowserExtensionActionPresentation] {
        guard let reordering, let tileLift else { return actions }
        let order = tileLift.shownOrder(actions.map(\.id), profileID: reordering.space.profileID)
        let byID = Dictionary(actions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byID[$0] }
    }

    /// The row's slots for `ids`, with the gap a tile carried from this strip
    /// holds open.
    private func slotLayout(for ids: [String]) -> BrowserPinnedExtensionSlotLayout {
        var layout = BrowserPinnedExtensionSlotLayout(ids: ids)
        if let reordering, let lift = tileLift?.lift, lift.landing == nil, lift.spaceID == reordering.space.id {
            layout.liftedID = lift.extensionID
            layout.gapIndex = lift.gapIndex
        }
        return layout
    }

    /// Whether the strip's tiles can be dragged now: it moves them, and it is
    /// the selected Space's.
    private var isReorderable: Bool {
        reordering != nil && isSelectedSpace != false
    }

    private func hidesTile(_ id: String) -> Bool {
        guard let reordering, let tileLift else { return false }
        return tileLift.hidesTile(id, in: reordering.space.id)
    }

    private func liftSource(
        for action: BrowserExtensionActionPresentation, order: [String]
    ) -> BrowserPinnedExtensionLiftSource {
        BrowserPinnedExtensionLiftSource(
            action: action, order: order, rowOrigin: rowOrigin,
            reordering: isReorderable ? reordering : nil, tileLift: tileLift)
    }
}

/// Lifts a pinned extension tile off its strip with the sidebar's own drag:
/// a drag that travels a few points lifts it, so a click still runs it.
private struct BrowserPinnedExtensionLiftSource: ViewModifier {
    // MARK: - Variables

    let action: BrowserExtensionActionPresentation
    /// The strip's tiles, in the order it shows them.
    let order: [String]
    /// Where the strip's first slot is in the window.
    let rowOrigin: CGPoint
    let reordering: BrowserPinnedExtensionActionList.Reordering?
    let tileLift: BrowserExtensionTileLiftState?

    /// Whether this tile's drag carries the tile now.
    @State private var ownsLift = false
    /// Whether this drag lost its lift, which the rest of it then leaves be.
    @State private var isRejected = false

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        if reordering != nil, tileLift != nil, order.count > 1 {
            content.modifier(BrowserPlatformSidebarReorderLiftGesture(moved: moved, released: released))
        } else {
            content
        }
    }

    // MARK: - Actions - Lifting

    /// Lifts the tile as the drag first moves, then carries it, holding open
    /// the slot its leading edge is nearest.
    private func moved(from start: CGPoint, to location: CGPoint) {
        guard !isRejected, let reordering, let tileLift else { return }
        if ownsLift {
            guard let lift = tileLift.lift, tileLift.isCarrying, lift.extensionID == action.id else {
                ownsLift = false
                isRejected = true
                return
            }
            tileLift.update(pointer: location, gapIndex: gapIndex(at: location, grabbing: lift.grabOffset))
            return
        }
        guard tileLift.lift == nil, let index = order.firstIndex(of: action.id) else {
            isRejected = true
            return
        }
        tileLift.begin(
            extensionID: action.id, spaceID: reordering.space.id, profileID: reordering.space.profileID,
            icon: action.icon, frame: BrowserPinnedExtensionSlotLayout.frame(ofSlot: index, from: rowOrigin),
            pointer: start, order: order)
        guard let lift = tileLift.lift, lift.extensionID == action.id else {
            isRejected = true
            return
        }
        ownsLift = true
        tileLift.update(pointer: location, gapIndex: gapIndex(at: location, grabbing: lift.grabOffset))
    }

    /// Lets the tile go onto the slot the gap holds, and moves it there.
    private func released() {
        defer {
            ownsLift = false
            isRejected = false
        }
        guard ownsLift, let reordering, let tileLift, tileLift.isCarrying, let lift = tileLift.lift else { return }
        let frame = BrowserPinnedExtensionSlotLayout.frame(ofSlot: lift.gapIndex, from: rowOrigin)
        guard let move = tileLift.drop(landingAt: frame) else { return }
        reordering.move(move.extensionID, move.beforeID)
    }

    private func gapIndex(at location: CGPoint, grabbing grabOffset: CGSize) -> Int {
        BrowserPinnedExtensionSlotLayout.slot(
            at: location.x - grabOffset.width, originX: rowOrigin.x, count: order.count)
    }
}
