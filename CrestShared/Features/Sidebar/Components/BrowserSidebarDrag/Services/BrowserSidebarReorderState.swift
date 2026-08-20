import CoreGraphics
import Foundation
import Observation

/// Live state for an in-view sidebar reorder: which item is lifted, where the
/// pointer is, and the target that resolves from the measured geometry.
///
/// This replaces the AppKit `NSDraggingSession` path for sidebar items. That path
/// could not render a drag image on macOS 27 — AppKit never created the drag
/// window — and its pan recognizer received no live movement, only a single
/// sample at mouse-up. A SwiftUI `DragGesture` streams continuously in the same
/// view tree, so the lift is drawn by us and is always visible.
@Observable
@MainActor
final class BrowserSidebarReorderState {
    struct Lift: Equatable, Sendable {
        let item: BrowserSidebarReorderItem
        let section: BrowserSidebarReorderSection
        /// Size of the lifted row, used to size the gap it leaves behind.
        let rowSize: CGSize
        /// Where inside the row the pointer grabbed it, so a morphing lift can
        /// settle under the cursor instead of at the row's leading edge.
        let grabOffset: CGSize
    }

    private(set) var lift: Lift?
    private(set) var pointer: CGPoint = .zero
    private(set) var resolvedTarget: BrowserSidebarReorderTarget?

    @ObservationIgnored
    private var rows: [BrowserSidebarReorderItemID: RegisteredRow] = [:]
    @ObservationIgnored
    private var zones: [UUID: BrowserSidebarReorderZone] = [:]

    /// A registered row together with the view that registered it, so a
    /// departing row cannot clear the registration its replacement just made.
    ///
    /// A row that changes section keeps its item identity: dragging a tab from
    /// the current list to the saved one, or into a folder, is an arriving view
    /// in the new section and a departing view in the old one. SwiftUI runs the
    /// departing view's `onDisappear` after the arriving one has measured
    /// itself — later still when the row it left is fading out — so a registry
    /// keyed by item alone loses the live registration to the stale removal.
    /// The row then has no geometry at all: nothing displaces around it, no
    /// insertion line anchors on it, and drops aim straight past it.
    private struct RegisteredRow {
        let owner: UUID
        let row: BrowserSidebarReorderRow
    }

    /// Where each presented card sits, in the same global space the zones and
    /// the pointer use.
    ///
    /// Separate from `rows` on purpose: a presented tab usually has a sidebar
    /// row as well, and one registry keyed by item would have the card and the
    /// row overwriting each other's frames. Separate from
    /// `BrowserSplitCardFrameRegistry` too, which answers the same question in
    /// the split surface's own named space for click-to-focus — a drag has to
    /// compare one pointer against sidebar zones and cards together, and only
    /// the global space can hold both.
    ///
    /// This registry is also the session state acceptance reads. How many cards
    /// are on show is whether the group is at capacity, and whether the dragged
    /// tab is among them is whether it is already presented — the same way
    /// `hasRoom` counts registered rows rather than asking the session.
    @ObservationIgnored
    private var splitCards: [TabID: SplitCard] = [:]

    /// A registered card frame together with the view that registered it, so a
    /// disappearing card cannot clear the registration its replacement just
    /// made. The content area swaps hosts mid-drag — a lone tab's surface
    /// becomes a one-card column — and SwiftUI runs the departing view's
    /// `onDisappear` after the arriving one has measured itself.
    private struct SplitCard {
        let owner: UUID
        let frame: CGRect
    }

    /// A lift the system drag may or may not begin. `.onDrag`'s provider runs at
    /// the press, before any drag exists — beginning the lift there hides the
    /// row while nothing is in flight yet, and a press released without pulling
    /// never produces a session, so nothing would ever clear it. The stage is
    /// inert until the drop delegate reports a real position.
    @ObservationIgnored
    private var stagedLift: (item: BrowserSidebarReorderItem, section: BrowserSidebarReorderSection)?

    /// True for a moment after a lift, so the row that was just dragged does not
    /// also fire its own tap. The lift and the row's button recognise
    /// simultaneously — deliberately, or the button would suppress the lift — so
    /// the touch-up at the end of a drag would otherwise open the tab.
    private(set) var isSuppressingActivation = false

    /// True from the moment the current drag first resolves a card insertion
    /// until it ends, whether or not the pointer is still over the content area.
    ///
    /// The content area answers this rather than `resolvedTarget` directly
    /// because a window presenting one tab has to change layout to show a drop
    /// placeholder beside it, and that change swaps the host its live web view
    /// belongs to. Letting it follow the pointer in and out would hand the same
    /// web view back and forth several times per drag. Entering is a one-way
    /// door for the length of the drag; the placeholder itself still comes and
    /// goes with the resolved target, which is only a width change.
    private(set) var hasEnteredSplitContent = false

    /// A row must ignore its own activation both while it is being dragged and
    /// for a moment after it lands.
    var suppressesActivation: Bool {
        isDragging || isSuppressingActivation
    }
    @ObservationIgnored private var activationSuppressionTask: Task<Void, Never>?

    var isDragging: Bool { lift != nil }

    func isLifted(_ id: BrowserSidebarReorderItemID) -> Bool {
        lift?.item.id == id
    }

    // MARK: - Geometry registration

    func register(row: BrowserSidebarReorderRow, owner: UUID) {
        // A drag offsets neighbouring rows without changing their layout slots.
        // Their global geometry therefore follows the presentation transform
        // while the animation runs. Freeze the resting registry at lift time so
        // those temporary frames cannot feed back into ordering and compound.
        guard !isDragging else { return }
        rows[row.id] = RegisteredRow(owner: owner, row: row)
    }

    func removeRow(_ id: BrowserSidebarReorderItemID, owner: UUID) {
        guard rows[id]?.owner == owner else { return }
        rows[id] = nil
    }

    /// Every row currently on show in one Space's sidebar, in no particular
    /// order. The policy sorts them into each section's reading order.
    ///
    /// Scoped to a Space because the registry is not: one state serves every
    /// sidebar its store puts on screen, and several of them register rows at
    /// once — a second window onto the same session, or the pages either side
    /// of a Space pager's visible one, which stay alive so a swipe can already
    /// show them. A section identity is only a placement, so those rows arrive
    /// in the same bucket as this drag's own. Every caller here is resolving
    /// one lift, and a lift orders itself among the rows of the Space it came
    /// from — see `BrowserSidebarReorderRow.space`.
    private func registeredRows(
        in space: BrowserSpaceRuntimeAssignment
    ) -> [BrowserSidebarReorderRow] {
        rows.values.map(\.row).filter { $0.space == space }
    }

    /// Zones are keyed by the registering view, not by target: the mobile space
    /// pager keeps neighbouring pages alive, and every page registers the same
    /// targets. Keyed by target, whichever page registered last would clobber
    /// the visible page's frames with offscreen ones.
    func register(zone: BrowserSidebarReorderZone, for id: UUID) {
        zones[id] = zone
    }

    func removeZone(for id: UUID) {
        zones[id] = nil
    }

    /// Records where one presented card is. The drop placeholder never
    /// registers: the index resolved against the cards has to stay put while
    /// the placeholder it opens shifts them.
    func register(splitCardFrame frame: CGRect, for tabID: TabID, owner: UUID) {
        splitCards[tabID] = SplitCard(owner: owner, frame: frame)
    }

    func removeSplitCardFrame(for tabID: TabID, owner: UUID) {
        guard splitCards[tabID]?.owner == owner else { return }
        splitCards[tabID] = nil
    }

    /// Where a registered row last measured itself, in the global space the
    /// pointer is reported in. The lift reads it to work out where inside the
    /// row the pointer grabbed; nothing else needs a row's geometry.
    func frame(ofRow id: BrowserSidebarReorderItemID) -> CGRect? {
        rows[id]?.row.frame
    }

    /// The presented cards in reading order, hidden duplicates excluded.
    var orderedSplitCardFrames: [CGRect] {
        BrowserSplitDropPolicy.ordered(splitCards.values.map(\.frame))
    }

    // MARK: - Drag lifecycle

    /// Remembers what a system drag would lift without lifting it.
    func stage(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection
    ) {
        stagedLift = (item, section)
    }

    func begin(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection,
        at pointer: CGPoint
    ) {
        let frame = frame(ofRow: item.id)
        lift = Lift(
            item: item,
            section: section,
            rowSize: frame?.size ?? .zero,
            grabOffset: CGSize(
                width: pointer.x - (frame?.minX ?? pointer.x),
                height: pointer.y - (frame?.minY ?? pointer.y)
            )
        )
        stagedLift = nil
        hasEnteredSplitContent = false
        self.pointer = pointer
        resolveTarget()
    }

    func update(pointer: CGPoint) {
        // A position from the drop delegate is the proof a staged drag is
        // genuinely in flight; promote it before applying the sample.
        if lift == nil, let staged = stagedLift {
            begin(item: staged.item, section: staged.section, at: pointer)
        }
        guard lift != nil else { return }
        self.pointer = pointer
        resolveTarget()
    }

    /// Clears the drag and returns the item and target to commit, if the drop
    /// resolved somewhere.
    func end() -> (
        item: BrowserSidebarReorderItem,
        target: BrowserSidebarReorderTarget
    )? {
        defer {
            if lift != nil { suppressActivation() }
            lift = nil
            stagedLift = nil
            resolvedTarget = nil
            hasEnteredSplitContent = false
        }
        guard let lift, let target = resolvedTarget else { return nil }
        return (lift.item, target)
    }

    func cancel() {
        if lift != nil { suppressActivation() }
        lift = nil
        stagedLift = nil
        resolvedTarget = nil
        hasEnteredSplitContent = false
    }

    /// Gives up a lift because something else took the touch that was carrying
    /// it — on a touch shell, the row's own context menu.
    ///
    /// Nothing else can end that lift. A touch lift is staged when `.onDrag`'s
    /// provider runs and promoted by the first position the drop delegate
    /// reports, and both of those belong to a system drag session; a menu that
    /// wins the press leaves the session either never begun or cancelled before
    /// it reports a phase, so `BrowserMobileReorderSessionModifier` hears
    /// nothing and no drop ever lands. Left alone the lift stays live for good —
    /// neighbours frozen at the offsets they stepped aside to, and the lifted
    /// row invisible in the slot it came from, under an open menu.
    ///
    /// Safe when there is nothing to give up: a lift that was only staged clears
    /// without suppressing the row's activation, because no drag ever happened.
    func yieldToCompetingInteraction() {
        cancel()
    }

    private func suppressActivation() {
        isSuppressingActivation = true
        activationSuppressionTask?.cancel()
        activationSuppressionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: BrowserSidebarReorderPolicy.activationSuppression
            )
            guard !Task.isCancelled else { return }
            self?.isSuppressingActivation = false
        }
    }

    // MARK: - Displacement

    /// How far the row for `id` steps aside for the current target.
    func displacement(for id: BrowserSidebarReorderItemID) -> CGSize {
        guard let context = insertionContext(for: id) else { return .zero }
        return BrowserSidebarReorderPolicy.displacement(
            candidateIndex: context.candidateIndex,
            draggedSlot: context.draggedSlot,
            insertionIndex: context.index,
            layout: BrowserSidebarReorderPolicy.slotLayout(
                for: context.ordered,
                fallbackStride: context.fallbackStride
            )
        )
    }

    /// Real layout height the destination list must add while an item arrives
    /// from another section. Row displacement alone is a presentation transform
    /// and cannot enlarge the section's measured frame.
    func incomingLiftReservationHeight(
        for section: BrowserSidebarReorderSection
    ) -> CGFloat {
        guard let lift,
            lift.section != section,
            resolvedTarget?.section == section,
            !section.flowsHorizontally
        else { return 0 }
        return max(0, lift.rowSize.height)
    }

    // MARK: - Drop indicator

    /// The insertion line for the current target, if it anchors on `id`.
    ///
    /// The line is drawn by the row next to the gap rather than by the section, so
    /// it travels with that row as it steps aside and always reads as the seam the
    /// lifted row will drop into.
    func indicator(
        for id: BrowserSidebarReorderItemID
    ) -> BrowserSidebarReorderIndicator? {
        guard let context = insertionContext(for: id) else { return nil }
        let flowsHorizontally = context.section.flowsHorizontally

        if context.candidateIndex == context.index {
            return BrowserSidebarReorderIndicator(
                side: .before,
                flowsHorizontally: flowsHorizontally
            )
        }
        // Dropping at the very end has no row after the gap, so the last row draws
        // the line on its trailing edge instead.
        if context.index >= context.candidateCount,
            context.candidateIndex == context.candidateCount - 1
        {
            return BrowserSidebarReorderIndicator(
                side: .after,
                flowsHorizontally: flowsHorizontally
            )
        }
        return nil
    }

    /// The insertion line a section draws for itself when it has no rows to
    /// anchor one on.
    ///
    /// `indicator(for:)` hands the line to the row beside the gap so it travels
    /// with that row as it steps aside. A section can have no such row: the
    /// unfiled saved run under a folder that holds every saved tab, a pinned
    /// grid nobody has filled, a current list that was just cleared. Those
    /// sections still accept a drop, and without a line they accept it in
    /// silence — the drag reads as refused right up until it lands.
    ///
    /// Only ever `.before`: an empty section inserts at index zero, so the line
    /// stands at the leading edge of the run — the top of a list, the leading
    /// side of a grid — which is where its first row would be.
    func emptySectionIndicator(
        for section: BrowserSidebarReorderSection
    ) -> BrowserSidebarReorderIndicator? {
        guard let lift,
            resolvedTarget?.section == section,
            BrowserSidebarReorderPolicy.rows(
                in: section,
                from: registeredRows(in: lift.item.spaceAssignment)
            )
            .allSatisfy({ $0.id == lift.item.id })
        else { return nil }
        return BrowserSidebarReorderIndicator(
            side: .before,
            flowsHorizontally: section.flowsHorizontally
        )
    }

    /// Whether a collapsed folder is the current drop target, so it can highlight.
    func isTargetedFolder(_ folderID: FolderID) -> Bool {
        resolvedTarget?.kind == .intoFolder(folderID)
    }

    // MARK: - Morphing

    /// The shape a lifted tab would take on release, so its lift can morph
    /// toward what it is about to become — a pinned tile, a page-shaped card, or
    /// back to a row.
    var liftTargetShape: BrowserTabDragPreviewShape? {
        guard let lift else { return nil }
        switch lift.item {
        case .tab:
            break
        case .folder, .splitGroup:
            // Neither shape changes with its destination: a folder is always a
            // folder row, and a split group is a stack of member lines wherever
            // it lands — it can never become a pinned tile, because pinned tabs
            // cannot be members. Both stay shape-stable and skip the morph.
            return nil
        }
        switch resolvedTarget?.kind {
        case .insert(let section, _, _):
            guard case .tabs(let placement, _) = section else { return nil }
            return .resting(for: placement)
        case .intoFolder:
            return .row
        case .splitInsert:
            return .webpageCard
        case .space, .none:
            // Nowhere resolved yet: hold the shape it started as.
            guard case .tabs(let placement, _) = lift.section else { return nil }
            return .resting(for: placement)
        }
    }

    /// The lift the window-level host draws, for as long as it is lifted.
    ///
    /// Non-`nil` for the whole of every promoted lift on the platform that draws
    /// its own — from the first pointer sample that promotes it to the release
    /// or cancel that ends it — and everywhere the pointer goes in between. A
    /// preview handed over part-way is a preview that is clipped up to the
    /// handover: by the page's web view, which outranks every SwiftUI sibling in
    /// the same host, but equally by window chrome, by the insets around the
    /// content area, and by whatever band a view transition is passing through.
    /// Owning the whole lift is what removes the seam rather than moving it.
    ///
    /// Tabs, folders, and split groups alike. Only a tab changes shape on the
    /// way — a folder is a folder row and a group is a stack of member lines
    /// wherever they land — but all three are pointer-chasing visuals, and all
    /// three are clipped by the same things.
    var floatingLift: BrowserSidebarFloatingLift? {
        guard BrowserSidebarReorderPolicy.drawsOwnLift, let lift else { return nil }
        let shape = liftTargetShape ?? .row
        return BrowserSidebarFloatingLift(
            item: lift.item,
            shape: shape,
            progress: shape == .row ? 0 : 1,
            pointer: pointer,
            grabOffset: lift.grabOffset,
            rowWidth: BrowserTabDragPreviewLayout.rowWidth(
                forSourceWidth: lift.rowSize.width
            )
        )
    }

    // MARK: - Resolution

    private struct InsertionContext {
        let section: BrowserSidebarReorderSection
        let ordered: [BrowserSidebarReorderRow]
        let candidateIndex: Int
        let candidateCount: Int
        let draggedSlot: Int
        let index: Int
        let fallbackStride: CGFloat
    }

    /// Shared setup for displacement and the drop indicator: both need the row's
    /// position within the target section, excluding the lifted row itself.
    private func insertionContext(
        for id: BrowserSidebarReorderItemID
    ) -> InsertionContext? {
        guard let lift,
            lift.item.id != id,
            let target = resolvedTarget,
            case .insert(let section, _, let index) = target.kind
        else { return nil }

        let ordered = BrowserSidebarReorderPolicy.rows(
            in: section,
            from: registeredRows(in: lift.item.spaceAssignment)
        )
        let candidates = ordered.filter { $0.id != lift.item.id }
        guard let candidateIndex = candidates.firstIndex(where: { $0.id == id })
        else { return nil }

        // A lifted row entering a different section has no slot of its own there,
        // so nothing sits "after" it and every candidate keeps its index.
        let draggedSlot =
            ordered.firstIndex { $0.id == lift.item.id } ?? candidates.count

        return InsertionContext(
            section: section,
            ordered: ordered,
            candidateIndex: candidateIndex,
            candidateCount: candidates.count,
            draggedSlot: draggedSlot,
            index: index,
            fallbackStride: section.usesGridOrdering
                ? lift.rowSize.width
                : lift.rowSize.height
        )
    }

    private func resolveTarget() {
        guard let lift else {
            resolvedTarget = nil
            return
        }
        guard
            let zone = BrowserSidebarReorderPolicy.zone(
                at: pointer,
                // An empty frame is a hidden duplicate of a live zone — an
                // offscreen pager page or a collapsed picker — never a target.
                in: zones.values.filter { !$0.frame.isEmpty },
                accepting: lift.item
            )
        else {
            resolvedTarget = nil
            return
        }

        switch zone.target {
        case .space(let assignment):
            resolvedTarget = BrowserSidebarReorderTarget(kind: .space(assignment))

        case .folder(let folderID):
            // A folder cannot be dropped into itself.
            resolvedTarget =
                lift.item.id == .folder(folderID)
                ? nil
                : BrowserSidebarReorderTarget(kind: .intoFolder(folderID))

        case .section(let section):
            let ordered = BrowserSidebarReorderPolicy.rows(
                in: section,
                from: registeredRows(in: lift.item.spaceAssignment)
            )
            // This Space's own rows, so a capped run is judged by what is in
            // it rather than by what every sidebar on screen adds up to.
            let existingCount = ordered.filter { $0.id != lift.item.id }.count
            guard
                BrowserSidebarReorderPolicy.hasRoom(
                    for: lift.item,
                    in: section,
                    existingCount: existingCount,
                    isAlreadyInSection: lift.section == section
                )
            else {
                resolvedTarget = nil
                return
            }
            let index = BrowserSidebarReorderPolicy.insertionIndex(
                at: pointer,
                orderedRows: ordered,
                excluding: lift.item.id
            )
            let anchor = BrowserSidebarReorderPolicy.insertionAnchor(
                index: index,
                orderedRows: ordered,
                excluding: lift.item.id
            )
            resolvedTarget = BrowserSidebarReorderTarget(
                kind: .insert(section: section, beforeID: anchor, index: index)
            )

        case .splitContent(let assignment):
            resolvedTarget = splitInsertTarget(
                assignment,
                in: zone.frame,
                for: lift
            )
            if resolvedTarget != nil { hasEnteredSplitContent = true }
        }
    }

    /// Where a tab would join the cards on show, or `nil` when it cannot.
    ///
    /// Every refusal here means no resolved target, and therefore no drop
    /// placeholder: an insertion point that the commit would decline is worse
    /// than none at all. The zone has already established that this is a tab
    /// from this Space; what is left is what the presented cards themselves say.
    ///
    /// Only the cards inside `contentFrame` are consulted. Windows share one
    /// reorder state, and two of them showing the same Space register two full
    /// sets of cards at different places on screen; counting them together
    /// would put the drop at the wrong index and report a two-card split as
    /// full. The zone the pointer resolved to is exactly one window's content
    /// area, so it is also the frame that says which cards this drag is between.
    private func splitInsertTarget(
        _ assignment: BrowserSpaceRuntimeAssignment,
        in contentFrame: CGRect,
        for lift: Lift
    ) -> BrowserSidebarReorderTarget? {
        guard case .tab(let item) = lift.item else { return nil }
        let cards = splitCards.filter {
            !$0.value.frame.isEmpty
                && contentFrame.contains(
                    CGPoint(x: $0.value.frame.midX, y: $0.value.frame.midY)
                )
        }
        guard
            // Nothing is presented — a locked Space, or a window with no
            // selected tab — so there is no card to join.
            !cards.isEmpty,
            // Already a card. Dropping a tab onto the split it is part of,
            // including a lone tab onto itself, changes nothing.
            cards[item.tabID] == nil,
            cards.count < BrowserSplitGroupPolicy.maximumMembers
        else { return nil }

        return BrowserSidebarReorderTarget(
            kind: .splitInsert(
                assignment: assignment,
                index: BrowserSplitDropPolicy.insertionIndex(
                    at: pointer,
                    orderedCardFrames: BrowserSplitDropPolicy.ordered(
                        cards.values.map(\.frame)
                    )
                )
            )
        )
    }
}
