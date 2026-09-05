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
        /// Visible descendants at pickup, relative to the lifted section.
        var previewRows: [BrowserSidebarReorderRow] = []
    }

    private(set) var lift: Lift?
    private(set) var pointer: CGPoint = .zero
    private(set) var resolvedTarget: BrowserSidebarReorderTarget?
    private(set) var layout = BrowserSidebarReorderLayout()
    private var lastPreviewShape: BrowserTabDragPreviewShape?
    private(set) var landingPreview: BrowserSidebarFloatingLift?
    private(set) var landingSessionToken: BrowserDragSessionToken?
    @ObservationIgnored private var landingExpirationTask: Task<Void, Never>?
    @ObservationIgnored private var needsLandingMeasurement = false
    @ObservationIgnored private var landingSection: BrowserSidebarReorderSection?

    func isRevealing(_ id: BrowserSidebarReorderItemID) -> Bool {
        landingPreview?.item.id == id && landingPreview?.landing?.isRevealing == true
    }

    func revealLanding(_ id: UUID) {
        guard landingPreview?.landing?.id == id else { return }
        landingPreview?.landing?.isRevealing = true
    }

    func hidesSource(_ id: BrowserSidebarReorderItemID) -> Bool {
        isLifted(id) || landingPreview?.item.id == id
    }

    func finishLanding(_ id: UUID) {
        guard landingPreview?.landing?.id == id else { return }
        landingPreview = nil
        landingSessionToken = nil
        needsLandingMeasurement = false
        landingSection = nil
        landingExpirationTask?.cancel()
        landingExpirationTask = nil
    }

    /// Native drop callbacks keep their session identity while layout refines
    /// the destination frame and replaces its animation identifier.
    func finishLanding(session: BrowserDragSessionToken) {
        guard landingSessionToken == session, let id = landingPreview?.landing?.id else { return }
        finishLanding(id)
    }

    @ObservationIgnored private var verticalDirection: CGFloat = 0

    @ObservationIgnored
    private var rows: [BrowserSidebarReorderItemID: RegisteredRow] = [:]
    @ObservationIgnored
    private var zones: [UUID: RegisteredZone] = [:]
    @ObservationIgnored
    private var scrollRegions: [UUID: CGRect] = [:]

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
        var row: BrowserSidebarReorderRow
        let scrollRegionID: UUID?
    }

    /// A zone remembers whether it belongs to a scrolling list. Its measured
    /// frame can extend far beyond that list when several saved folders are
    /// expanded, but only the portion inside the viewport is a real target.
    private struct RegisteredZone {
        var zone: BrowserSidebarReorderZone
        let scrollRegionID: UUID?
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
    /// `hasRoom` counts registered rows rather than asking the session. And for
    /// the same reason as `hasRoom`, a count is only ever taken of one Space's
    /// own cards: see `SplitCard.space`.
    @ObservationIgnored
    private var splitCards: [TabID: SplitCard] = [:]

    /// A registered card frame together with the view that registered it, so a
    /// disappearing card cannot clear the registration its replacement just
    /// made. The content area swaps hosts mid-drag — a lone tab's surface
    /// becomes a one-card column — and SwiftUI runs the departing view's
    /// `onDisappear` after the arriving one has measured itself.
    private struct SplitCard {
        let owner: UUID

        /// The Space whose presentation this card stands in.
        ///
        /// A card outlives the presentation that put it there. The content area
        /// shows one Space at a time, and switching Space replaces every card in
        /// it — but the arriving cards measure themselves before SwiftUI runs the
        /// departing ones' `onDisappear`, which is the same ordering the owner
        /// stamp above exists for. For a moment, and longer while the change is
        /// animating, the registry holds both Spaces' cards. The registry is
        /// keyed by tab and two Spaces share no tabs, so nothing collides and
        /// nothing is overwritten: they simply add up.
        ///
        /// Which is why the card has to say whose it is. Counted together, a pair
        /// of two-card splits reaches `BrowserSplitGroupPolicy.maximumMembers`
        /// and the drag is refused a split that has room to spare — in silence,
        /// since a refused target means no placeholder, no insertion line, and no
        /// reason given — and the index a drop does resolve is counted against
        /// cards from a Space the pointer is not over.
        let space: BrowserSpaceRuntimeAssignment

        let frame: CGRect
    }

    /// A lift the system drag may or may not begin. `.onDrag`'s provider runs at
    /// the press, before any drag exists — beginning the lift there hides the
    /// row while nothing is in flight yet, and a press released without pulling
    /// never produces a session, so nothing would ever clear it. The stage is
    /// inert until the drop delegate reports a real position.
    ///
    /// Observed, unlike the rest of the staging bookkeeping, because the Space
    /// pager has to stop paging from the moment the drag begins rather than
    /// from the moment it resolves. Waiting for promotion is too late: the strip
    /// is live for the whole first stretch of the drag, and reaching its edge
    /// there pages to another Space mid-lift. Nothing else reads the stage, so
    /// what this costs is one re-evaluation of the pager's `scrollDisabled` per
    /// drag — a property change on an ancestor scroll view, not a rebuild of the
    /// row the drag interaction is carrying.
    private var stagedLift: (item: BrowserSidebarReorderItem, section: BrowserSidebarReorderSection)?

    /// Writes off a stage no drag ever came back for. See
    /// `BrowserSidebarReorderPolicy.stagedLiftExpiration`.
    @ObservationIgnored private var stagedLiftExpirationTask: Task<Void, Never>?

    /// How long this state waits before writing off an unpromoted stage.
    @ObservationIgnored private let stagedLiftExpiration: Duration

    init(
        stagedLiftExpiration: Duration = BrowserSidebarReorderPolicy
            .stagedLiftExpiration
    ) {
        self.stagedLiftExpiration = stagedLiftExpiration
    }

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

    /// Whether this state is carrying a lift at all — one the system drag has
    /// staged and not yet promoted, or one already moving.
    ///
    /// Broader than `isDragging` on purpose. `isDragging` answers "is a row out
    /// of its slot", which is what displacement and the drop indicator want.
    /// This answers "is a drag under way", which is what anything that has to
    /// hold still for the length of one wants — the Space pager above all, since
    /// the stretch between staging and promotion is exactly when a finger is
    /// still travelling toward the edge.
    var hasLiftInFlight: Bool { lift != nil || stagedLift != nil }

    @ObservationIgnored private var sessionGeneration: UInt64 = 0

    var sessionToken: BrowserDragSessionToken? {
        hasLiftInFlight ? BrowserDragSessionToken(generation: sessionGeneration) : nil
    }

    func isLifted(_ id: BrowserSidebarReorderItemID) -> Bool {
        lift?.item.id == id
    }

    // MARK: - Geometry registration

    func register(
        row: BrowserSidebarReorderRow,
        owner: UUID,
        scrollRegionID: UUID? = nil
    ) {
        // A drag offsets neighbouring rows without changing their layout slots.
        // Their global geometry therefore follows the presentation transform
        // while the animation runs. Freeze the resting registry at lift time so
        // those temporary frames cannot feed back into ordering and compound.
        // A lazy row first revealed by scrolling during the lift has no resting
        // registration to freeze, though, so accept that first measurement.
        guard !isDragging || rows[row.id] == nil else { return }
        rows[row.id] = RegisteredRow(
            owner: owner,
            row: row,
            scrollRegionID: scrollRegionID
        )
        if needsLandingMeasurement, var preview = landingPreview, preview.item.id == row.id,
            !row.frame.isEmpty, landingSection == nil || landingSection == row.section,
            preview.landing?.frame != row.frame, preview.landing?.isRevealing != true
        {
            preview.landing = BrowserSidebarReorderLanding(frame: row.frame)
            landingPreview = preview
        }
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
    func register(
        zone: BrowserSidebarReorderZone,
        for id: UUID,
        scrollRegionID: UUID? = nil
    ) {
        guard !isDragging || zones[id] == nil else { return }
        zones[id] = RegisteredZone(
            zone: zone,
            scrollRegionID: scrollRegionID
        )
    }

    func removeZone(for id: UUID) {
        zones[id] = nil
    }

    /// Registers one visible ScrollView frame. Rows and zones beneath that
    /// region carry its identity through the environment; fixed pinned chrome
    /// does not, so it remains targetable while offscreen saved content is cut
    /// away from the same global coordinate space.
    func register(scrollRegionFrame frame: CGRect, for id: UUID) {
        scrollRegions[id] = frame
        if isDragging { resolveTarget() }
    }

    func removeScrollRegion(for id: UUID) {
        scrollRegions[id] = nil
        rows = rows.filter { $0.value.scrollRegionID != id }
        zones = zones.filter { $0.value.scrollRegionID != id }
        if isDragging { resolveTarget() }
    }

    /// Keeps frozen resting geometry aligned with a scroll that occurs during a
    /// lift. Normal geometry callbacks remain frozen because neighbour offsets
    /// are presentation transforms; the scroll observer reports the one uniform
    /// translation that is safe to apply to every row and zone in the region.
    func scrollableContentDidMove(in id: UUID, by offsetY: CGFloat) {
        guard isDragging, offsetY != 0 else { return }

        for key in Array(rows.keys) where rows[key]?.scrollRegionID == id {
            guard var registration = rows[key] else { continue }
            registration.row = BrowserSidebarReorderRow(
                id: registration.row.id,
                space: registration.row.space,
                section: registration.row.section,
                frame: registration.row.frame.offsetBy(dx: 0, dy: offsetY)
            )
            rows[key] = registration
        }

        for key in Array(zones.keys) where zones[key]?.scrollRegionID == id {
            guard var registration = zones[key] else { continue }
            registration.zone = BrowserSidebarReorderZone(
                target: registration.zone.target,
                frame: registration.zone.frame.offsetBy(dx: 0, dy: offsetY)
            )
            zones[key] = registration
        }

        refreshLayout()
        resolveTarget()
    }

    private var visibleZones: [BrowserSidebarReorderZone] {
        let pinned = pinnedGeometry
        return zones.values.compactMap { registration in
            let projected: CGRect?
            if case .section(let section) = registration.zone.target, section.usesGridOrdering,
                let pinned, registration.zone.frame.intersects(pinned.frame)
            {
                projected = CGRect(
                    origin: pinned.frame.origin,
                    size: CGSize(width: pinned.frame.width, height: max(pinned.layout.height, pinned.emptyHeight)))
            } else {
                projected = layout.frame(for: registration.zone)
            }
            guard let frame = projected else { return nil }
            guard let regionID = registration.scrollRegionID else {
                return BrowserSidebarReorderZone(target: registration.zone.target, frame: frame)
            }
            guard let viewport = scrollRegions[regionID] else { return nil }
            let visibleFrame = frame.intersection(viewport)
            guard !visibleFrame.isNull, !visibleFrame.isEmpty else { return nil }
            return BrowserSidebarReorderZone(
                target: registration.zone.target,
                frame: visibleFrame
            )
        }
    }

    func pinnedLayout(ids: [BrowserSidebarReorderItemID], in space: BrowserSpaceRuntimeAssignment)
        -> BrowserPinnedTabReorderLayout
    {
        guard let lift, lift.item.spaceAssignment == space, case .tab = lift.item else {
            return BrowserPinnedTabReorderLayout(ids: ids)
        }
        var result = BrowserPinnedTabReorderLayout(ids: ids, liftedID: lift.item.id)
        if case .insert(let section, _, let index) = resolvedTarget?.kind, section.usesGridOrdering {
            result.insertionIndex = index
        }
        return result
    }

    private var pinnedGeometry: (layout: BrowserPinnedTabReorderLayout, frame: CGRect, emptyHeight: CGFloat)? {
        guard let lift, let source = rows[lift.item.id]?.row.frame else { return nil }
        let section = BrowserSidebarReorderSection.tabs(placement: .pinned, folderID: nil)
        guard let zone = restingZone(for: section, inColumn: source) else { return nil }
        let ordered = BrowserSidebarReorderPolicy.rows(in: section, from: registeredRows(in: lift.item.spaceAssignment))
        let emptyHeight = max(zone.minimumHeight, ordered.isEmpty ? zone.frame.height : 0)
        return (pinnedLayout(ids: ordered.map(\.id), in: lift.item.spaceAssignment), zone.frame, emptyHeight)
    }

    /// Records where one presented card is, and which Space is presenting it. The
    /// drop placeholder never registers: the index resolved against the cards has
    /// to stay put while the placeholder it opens shifts them.
    func register(
        splitCardFrame frame: CGRect,
        for tabID: TabID,
        in space: BrowserSpaceRuntimeAssignment,
        owner: UUID
    ) {
        splitCards[tabID] = SplitCard(owner: owner, space: space, frame: frame)
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
        cancel()
        sessionGeneration &+= 1
        stagedLift = (item, section)
        armStagedLiftExpiration()
    }

    /// Starts the clock on the stage just recorded, replacing any earlier one.
    ///
    /// Only ever collects a stage that is still a stage. A promotion, a drop,
    /// and a cancel all cancel this first, and the guard is what covers the
    /// remaining race: a task already resumed when one of them lands would
    /// otherwise clear the lift they just recorded.
    private func armStagedLiftExpiration() {
        stagedLiftExpirationTask?.cancel()
        let delay = stagedLiftExpiration
        stagedLiftExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            stagedLiftExpirationTask = nil
            guard lift == nil else { return }
            stagedLift = nil
        }
    }

    private func cancelStagedLiftExpiration() {
        stagedLiftExpirationTask?.cancel()
        stagedLiftExpirationTask = nil
    }

    func begin(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection,
        at pointer: CGPoint
    ) {
        if stagedLift?.item.id != item.id || stagedLift?.section != section {
            sessionGeneration &+= 1
        }
        if let id = landingPreview?.landing?.id { finishLanding(id) }
        let frame = frame(ofRow: item.id)
        lift = Lift(
            item: item,
            section: section,
            rowSize: frame?.size ?? .zero,
            grabOffset: CGSize(
                width: pointer.x - (frame?.minX ?? pointer.x),
                height: pointer.y - (frame?.minY ?? pointer.y)
            ),
            previewRows: folderPreviewRows(for: item)
        )
        stagedLift = nil
        cancelStagedLiftExpiration()
        hasEnteredSplitContent = false
        verticalDirection = 0
        lastPreviewShape = nil
        self.pointer = pointer
        // Initially retain the original slot; subsequent samples move this one
        // gap. Descendants of an expanded lift never become drop targets.
        if let frame {
            layout = BrowserSidebarReorderLayout(
                sourceID: item.id, sourceFrame: frame,
                hiddenIDs: Set((lift?.previewRows.map(\.id) ?? []) + [item.id]), sourceIsGrid: section.usesGridOrdering)
            let ordered = BrowserSidebarReorderPolicy.rows(in: section, from: registeredRows(in: item.spaceAssignment))
            let candidates = ordered.filter { !layout.hiddenIDs.contains($0.id) }
            let index = ordered.prefix { $0.id != item.id }.filter { !layout.hiddenIDs.contains($0.id) }.count
            resolvedTarget = BrowserSidebarReorderTarget(
                kind: .insert(
                    section: section, beforeID: candidates.dropFirst(index).first?.id, index: index))
            refreshLayout()
            lastPreviewShape = liftTargetShape
        } else {
            resolveTarget()
        }
    }

    /// The row registry already describes precisely what an expanded folder
    /// shows, including kept collapsed tabs and nested/split groups.
    func folderPreviewRows(for item: BrowserSidebarReorderItem) -> [BrowserSidebarReorderRow] {
        guard case .folder = item, let frame = frame(ofRow: item.id) else { return [] }
        return registeredRows(in: item.spaceAssignment)
            .filter { $0.id != item.id && frame.contains($0.frame) && $0.frame.minY > frame.minY }
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { row in
                BrowserSidebarReorderRow(
                    id: row.id, space: row.space, section: row.section,
                    frame: row.frame.offsetBy(dx: -frame.minX, dy: -frame.minY))
            }
    }

    func update(pointer: CGPoint) {
        // A position from the drop delegate is the proof a staged drag is
        // genuinely in flight; promote it before applying the sample.
        if lift == nil, let staged = stagedLift {
            begin(item: staged.item, section: staged.section, at: pointer)
        }
        guard lift != nil else { return }
        let delta = pointer.y - self.pointer.y
        if abs(delta) > 0.5 { verticalDirection = delta > 0 ? 1 : -1 }
        self.pointer = pointer
        resolveTarget()
    }

    /// Clears the drag and returns the item and target to commit, if the drop
    /// resolved somewhere.
    func end(
        retainingPreview: Bool = false, landingTimeout: Duration? = .seconds(1),
        suppressReleaseActivation: Bool = true
    ) -> (
        item: BrowserSidebarReorderItem,
        target: BrowserSidebarReorderTarget
    )? {
        if retainingPreview, var preview = liftPreview, let frame = landingFrame {
            preview.landing = BrowserSidebarReorderLanding(frame: frame)
            landingPreview = preview
            landingSessionToken = sessionToken
            needsLandingMeasurement = true
            landingSection = resolvedTarget == nil ? lift?.section : resolvedTarget?.section
            landingExpirationTask?.cancel()
            landingExpirationTask = nil
            // A custom presenter has a bounded fallback. Native presenters use
            // their destination animation's completion callback.
            if let landingTimeout {
                landingExpirationTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: landingTimeout)
                    guard !Task.isCancelled, let self, let id = landingPreview?.landing?.id else { return }
                    finishLanding(id)
                }
            }
        }
        defer {
            if lift != nil, suppressReleaseActivation { suppressActivation() }
            lift = nil
            stagedLift = nil
            cancelStagedLiftExpiration()
            resolvedTarget = nil
            layout = BrowserSidebarReorderLayout()
            lastPreviewShape = nil
            hasEnteredSplitContent = false
        }
        guard let lift, let target = resolvedTarget else { return nil }
        return (lift.item, target)
    }

    /// A native completion can arrive after another lift or a committed drop.
    func cancel(session: BrowserDragSessionToken) {
        guard sessionToken == session else { return }
        cancel()
    }

    func cancel() {
        if let id = landingPreview?.landing?.id { finishLanding(id) }
        if lift != nil { suppressActivation() }
        lift = nil
        stagedLift = nil
        cancelStagedLiftExpiration()
        resolvedTarget = nil
        layout = BrowserSidebarReorderLayout()
        lastPreviewShape = nil
        hasEnteredSplitContent = false
    }

    /// Gives up a lift because something else took the touch that was carrying
    /// it — on a touch shell, the row's own context menu.
    ///
    /// A source provider can stage a lift before UIKit decides whether the
    /// touch becomes a drag or a context menu. The menu releases that pending
    /// state immediately; a native completion arriving later is token guarded.
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
        if let row = rows[id]?.row, row.usesGridOrdering, row.space == lift?.item.spaceAssignment,
            let pinned = pinnedGeometry, let frame = pinned.layout.frame(for: .tab(id), in: pinned.frame)
        {
            return CGSize(width: frame.minX - row.frame.minX, height: frame.minY - row.frame.minY)
        }
        if layout.isActive, let row = rows[id]?.row, !row.usesGridOrdering,
            row.space == lift?.item.spaceAssignment, let frame = layout.frame(for: row)
        {
            return CGSize(width: frame.minX - row.frame.minX, height: frame.minY - row.frame.minY)
        }
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
        guard !layout.isActive, let lift,
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
        case .intoFolder, .createCurrentFolder:
            return .row
        case .splitInsert:
            return .webpageCard
        case .space, .none:
            // A small overshoot outside the grid must not expand a tile back
            // into a wide row at the left edge of the window.
            if lastPreviewShape == .pinnedTile { return .pinnedTile }
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
        guard BrowserSidebarReorderPolicy.drawsOwnLift else { return nil }
        return liftPreview
    }

    /// Both native and SwiftUI presenters use the same measured geometry.
    var liftPreview: BrowserSidebarFloatingLift? {
        if let landingPreview { return landingPreview }
        guard let lift else { return nil }
        let shape = liftTargetShape ?? .row
        let pinned = pinnedGeometry
        var previewGrid = pinned?.layout
        if shape == .pinnedTile, previewGrid?.insertionIndex == nil { previewGrid?.insertionIndex = 0 }
        let pinnedSize =
            pinned.flatMap { previewGrid?.frame(for: .gap, in: $0.frame)?.size }
            ?? BrowserTabDragPreviewLayout.pinnedSize
        return BrowserSidebarFloatingLift(
            item: lift.item,
            shape: shape,
            progress: shape == .row ? 0 : 1,
            pointer: pointer,
            grabOffset: lift.grabOffset,
            rowWidth: lift.section.usesGridOrdering
                ? pinned?.frame.width ?? BrowserTabDragPreviewLayout.defaultRowWidth
                : max(lift.rowSize.width, 1),
            sourceSize: lift.rowSize,
            previewRows: lift.previewRows,
            pinnedTileSize: pinnedSize,
            sidebarBounds: pinned?.frame
        )
    }

    private var landingFrame: CGRect? {
        guard let lift else { return nil }
        switch resolvedTarget?.kind {
        case .insert(let section, _, _):
            if section.usesGridOrdering, let pinned = pinnedGeometry {
                return pinned.layout.frame(for: .gap, in: pinned.frame)
            }
            return layout.gapFrame
        case .intoFolder(let id):
            return rows[.folder(id)].flatMap { layout.frame(for: $0.row) }
        case .createCurrentFolder(let id):
            return rows[.tab(id)].flatMap { layout.frame(for: $0.row) }
        case .none:
            return rows[lift.item.id]?.row.frame
        case .space, .splitInsert:
            return nil
        }
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
        let previousTarget = resolvedTarget
        defer {
            if resolvedTarget != previousTarget { refreshLayout() }
            if resolvedTarget != nil { lastPreviewShape = liftTargetShape }
        }
        guard let lift else {
            resolvedTarget = nil
            return
        }
        // A stationary pointer in the open slot must not retarget itself just
        // because its neighbours animated around it.
        let point = insertionProbe(for: lift)
        if let gap = layout.gapFrame, gap.contains(point) { return }
        if let pinned = pinnedGeometry, let gap = pinned.layout.frame(for: .gap, in: pinned.frame),
            gap.contains(pointer)
        {
            return
        }
        let available = visibleZones.filter { !$0.frame.isEmpty && allowsNesting(in: $0, for: lift) }
        // Directly aiming at a collapsed folder still means filing into it.
        // Its middle band is distinct from the surrounding insertion slots.
        let direct = BrowserSidebarReorderPolicy.zone(at: pointer, in: available, accepting: lift.item)
        let nesting: BrowserSidebarReorderZone? =
            switch direct?.target {
            case .folder, .currentFolder, .currentTab: direct
            default: nil
            }
        guard
            let zone = nesting
                ?? BrowserSidebarReorderPolicy.zone(
                    at: point, in: available, accepting: lift.item
                )
        else {
            resolvedTarget = nil
            return
        }

        switch zone.target {
        case .currentTab(let tabID):
            resolvedTarget = BrowserSidebarReorderTarget(kind: .createCurrentFolder(tabID))
        case .space(let assignment):
            resolvedTarget = BrowserSidebarReorderTarget(kind: .space(assignment))

        case .folder(let folderID), .currentFolder(let folderID):
            // A folder cannot be dropped into itself.
            resolvedTarget =
                lift.item.id == .folder(folderID)
                ? nil
                : BrowserSidebarReorderTarget(kind: .intoFolder(folderID))

        case .section(let section):
            let pinned = pinnedGeometry
            let ordered = BrowserSidebarReorderPolicy.rows(
                in: section,
                from: registeredRows(in: lift.item.spaceAssignment).compactMap { row in
                    let frame: CGRect?
                    if row.usesGridOrdering, let pinned {
                        frame = pinned.layout.frame(for: .tab(row.id), in: pinned.frame)
                    } else {
                        frame = layout.frame(for: row)
                    }
                    guard let frame else { return nil }
                    return BrowserSidebarReorderRow(id: row.id, space: row.space, section: row.section, frame: frame)
                }
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
                at: point,
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
            resolvedTarget = splitInsertTarget(assignment, for: lift)
            if resolvedTarget != nil { hasEnteredSplitContent = true }
        }
    }

    /// Tall blocks cross a neighbour with their moving edge. Requiring a
    /// pointer grabbed at the header to traverse the entire expanded folder
    /// makes the old gap appear stuck even though its contents have moved.
    private func insertionProbe(for lift: Lift) -> CGPoint {
        guard layout.isActive, lift.rowSize.height > CrestLayout.sidebarRowHeight * 1.5,
            verticalDirection != 0
        else { return pointer }
        let top = pointer.y - lift.grabOffset.height
        return CGPoint(x: pointer.x, y: verticalDirection > 0 ? top + lift.rowSize.height : top)
    }

    /// A vertical folder drag stays among siblings. Moving right admits a
    /// deeper run; otherwise every expanded folder's body would steal a drag
    /// that is simply passing it. A collapsed header remains a direct target.
    private func allowsNesting(in zone: BrowserSidebarReorderZone, for lift: Lift) -> Bool {
        guard case .folder = lift.item, case .section(let section) = zone.target else { return true }
        let startX = layout.sourceFrame.minX + lift.grabOffset.width
        let extraDepth = max(0, Int((pointer.x - startX) / BrowserFolderLayout.nestingIndent))
        return folderDepth(of: section) <= folderDepth(of: lift.section) + extraDepth
    }

    private func folderDepth(of section: BrowserSidebarReorderSection) -> Int {
        var ancestors: Set<FolderID> = []
        var parent = section.parentFolderID
        while let id = parent, ancestors.insert(id).inserted {
            parent = rows[.folder(id)]?.row.section.parentFolderID
        }
        return ancestors.count
    }

    /// Rebuilt only when the destination changes, never once per rendered row.
    /// Frames are resting measurements; animation callbacks cannot feed their
    /// intermediate positions back into the next insertion decision.
    private func refreshLayout() {
        guard let lift, layout.isActive else { return }
        var next = layout
        next.sourceFrame = rows[lift.item.id]?.row.frame ?? layout.sourceFrame
        if let pinned = pinnedGeometry {
            next.gridFrame = pinned.frame
            next.gridHeightDelta =
                lift.section.usesGridOrdering || resolvedTarget?.section?.usesGridOrdering == true
                ? max(pinned.emptyHeight, pinned.layout.height) - pinned.frame.height : 0
        }
        next.gap = nil
        if case .insert(let section, let beforeID, _) = resolvedTarget?.kind,
            !section.usesGridOrdering
        {
            let candidates = BrowserSidebarReorderPolicy.rows(
                in: section, from: registeredRows(in: lift.item.spaceAssignment)
            ).filter { !next.hiddenIDs.contains($0.id) }
            let anchor: BrowserSidebarReorderLayout.Gap.Anchor
            let frame: CGRect
            if let beforeID, let row = candidates.first(where: { $0.id == beforeID }) {
                anchor = .before(beforeID)
                frame = row.frame
            } else if let row = candidates.last {
                anchor = .after(row.id)
                frame = CGRect(x: row.frame.minX, y: row.frame.maxY, width: row.frame.width, height: 0)
            } else if let zone = restingZone(for: section, inColumn: next.sourceFrame) {
                anchor = .emptySection(section)
                frame = CGRect(x: zone.frame.minX, y: zone.frame.maxY, width: zone.frame.width, height: 0)
            } else {
                if next != layout { layout = next }
                return
            }
            var parents: Set<FolderID> = []
            var parent = section.parentFolderID
            while let id = parent, parents.insert(id).inserted {
                parent = rows[.folder(id)]?.row.section.parentFolderID
            }
            next.gap = BrowserSidebarReorderLayout.Gap(
                section: section, anchor: anchor, frame: frame, containingFolders: parents)
        }
        if next != layout { layout = next }
    }

    private func restingZone(for section: BrowserSidebarReorderSection, inColumn frame: CGRect)
        -> BrowserSidebarReorderZone?
    {
        let target = BrowserSidebarReorderZone.Target.section(section)
        let matching = zones.values.map { $0.zone }.filter { zone in
            zone.target == target && zone.frame.maxX > frame.minX && zone.frame.minX < frame.maxX
        }
        return matching.min { $0.frame.height < $1.frame.height }
    }

    /// Where a tab would join the cards on show, or `nil` when it cannot.
    ///
    /// Every refusal here means no resolved target, and therefore no drop
    /// placeholder: an insertion point that the commit would decline is worse
    /// than none at all. The zone has already established that this is a tab
    /// from this Space; what is left is what the presented cards themselves say.
    ///
    /// Only `assignment`'s own cards are consulted — the Space the content area
    /// under the pointer is presenting. The registry holds more than that: a
    /// Space change replaces every card in the content area, and the arriving
    /// cards measure themselves before the departing ones disappear, so both
    /// Spaces' cards are registered together for as long as the change takes to
    /// animate. See `SplitCard.space` for what counting them together does.
    ///
    /// Geometry used to stand in for this, by consulting only the cards whose
    /// centre lay inside the resolved zone's frame. It cannot: the content area
    /// does not move an inch when the Space in it changes, so both Spaces' cards
    /// sit inside the very same rectangle. Nor was the case it was written for —
    /// two windows onto one session, showing the same Space at different places
    /// on screen — one a rectangle could have separated, because the frames it
    /// compares are measured in SwiftUI's `.global` space, which is the window's
    /// own and identical between two windows of a size. That case cannot reach
    /// here at all, in fact: this registry is keyed by tab, so a second window
    /// showing the same Space registers the same tabs and overwrites rather than
    /// adds — a card's registry identity is its tab, not its window, exactly as
    /// a row's is its item. What containment did still do was drop a genuine card
    /// whose centre had drifted out of the content area while the row animated,
    /// which undercounts a full group into looking as though it had room.
    private func splitInsertTarget(
        _ assignment: BrowserSpaceRuntimeAssignment,
        for lift: Lift
    ) -> BrowserSidebarReorderTarget? {
        guard case .tab(let item) = lift.item else { return nil }
        let cards = splitCards.filter {
            $0.value.space == assignment && !$0.value.frame.isEmpty
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
