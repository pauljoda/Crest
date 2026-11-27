import CoreGraphics
import Foundation
import Observation

/// Resting measurements for one window; registrations retain their view owner.
///
/// Rows and cards are kept per Space. The Spaces of a group show the pinned
/// tabs they share under the same IDs, and the pager keeps the pages beside
/// the shown one alive, so a Sub-Space's page measuring a shared pin must not
/// take the place of the shown Space's tile.
@Observable
@MainActor
final class BrowserSidebarReorderGeometry {
    // MARK: - Types

    struct RegisteredRow {
        let owner: UUID
        var row: BrowserSidebarReorderRow
        let scrollRegionID: UUID?
        var isContentRelative = false
    }

    struct RegisteredZone {
        var zone: BrowserSidebarReorderZone
        let sidebarViewportID: UUID?
        let scrollRegionID: UUID?
        var isContentRelative = false
    }

    struct RegisteredSelectionTarget {
        let itemID: BrowserSelectionItemID
        let space: BrowserSpaceRuntimeAssignment
        var frame: CGRect
        let sidebarViewportID: UUID?
        let scrollRegionID: UUID?
        var isContentRelative = false
    }

    /// Fixed-stride run of tab rows rendered through a recycled slot pool,
    /// providing exact row geometry and hit targets without per-row geometry
    /// observers or registration churn while scrolling.
    struct VirtualRowRun {
        let id: UUID
        let space: BrowserSpaceRuntimeAssignment
        let section: BrowserSidebarReorderSection
        let scrollRegionID: UUID?
        var frame: CGRect
        var rowStride: CGFloat
        var itemIDs: [BrowserSidebarReorderItemID]
        var itemIndexByID: [BrowserSidebarReorderItemID: Int]
        var visibleIndices: Range<Int>
        var auxiliaryClick: (@MainActor (UUID) -> Void)?

        func row(at index: Int) -> BrowserSidebarReorderRow {
            BrowserSidebarReorderRow(
                id: itemIDs[index],
                space: space,
                section: section,
                frame: CGRect(
                    x: frame.minX,
                    y: frame.minY + CGFloat(index) * rowStride,
                    width: frame.width,
                    height: rowStride
                ),
                parentItemID: nil
            )
        }
    }

    /// What a view measured while a lift held its registration still, and
    /// when, among the others held.
    struct HeldRow {
        let order: Int
        let registration: RegisteredRow
    }

    struct SplitCard {
        let owner: UUID
        let space: BrowserSpaceRuntimeAssignment
        let frame: CGRect
    }

    /// One Space's registration of an item: a row, or the card showing a tab.
    struct Key<ID: Hashable>: Hashable {
        let id: ID
        let space: BrowserSpaceRuntimeAssignment
    }

    // MARK: - Static Variables

    /// Rows within this vertical distance share a selection line.
    static let selectionLineTolerance: CGFloat = 2

    // MARK: - Variables

    private(set) var selectionRowsRevision = 0
    /// Advances with every change to the rows, so what is worked out from
    /// them can be kept until they change.
    @ObservationIgnored private(set) var rowsRevision = 0
    /// Each Space's rows, by item.
    @ObservationIgnored private var rows:
        [BrowserSpaceRuntimeAssignment: [BrowserSidebarReorderItemID: RegisteredRow]] = [:]
    {
        didSet { rowsRevision &+= 1 }
    }
    /// Registrations a later one replaced while their view was still on
    /// screen, by item and view. A row that moves between lists is two views
    /// for a moment, and the departing one can measure itself again during its
    /// exit, after the arriving one did; when it leaves, the item falls back to
    /// the view that stays instead of losing its frame.
    @ObservationIgnored private var replacedRows: [Key<BrowserSidebarReorderItemID>: [UUID: RegisteredRow]] = [:]
    /// The Space each view measured its row in, so a view whose Space changes
    /// profile takes its registration along rather than leaving it behind.
    @ObservationIgnored private var rowSpaces: [UUID: BrowserSpaceRuntimeAssignment] = [:]
    @ObservationIgnored private(set) var zones: [UUID: RegisteredZone] = [:]
    @ObservationIgnored private var selectionTargets: [UUID: RegisteredSelectionTarget] = [:]
    /// Per-tab auxiliary click handlers registered by `BrowserSidebarTabRow`,
    /// hit-tested against the row's already-measured reorder frame so tab rows
    /// need neither a duplicate geometry observer nor a per-row gesture bridge.
    @ObservationIgnored private var rowAuxiliaryClickHandlers:
        [BrowserSpaceRuntimeAssignment: [BrowserSidebarReorderItemID: @MainActor () -> Void]] = [:]
    /// Per-tab selection overrides when a tab row is disabled for selection
    /// (for example while renaming).
    @ObservationIgnored private var disabledSelectionRows:
        [BrowserSpaceRuntimeAssignment: Set<BrowserSidebarReorderItemID>] = [:]
    /// Fixed-stride recycled tab runs, keyed by Space and run ID.
    @ObservationIgnored private var virtualRuns: [BrowserSpaceRuntimeAssignment: [UUID: VirtualRowRun]] = [:]
    @ObservationIgnored private(set) var scrollRegions: [UUID: CGRect] = [:]
    /// The live global origin of each scrolling list's content coordinate space.
    @ObservationIgnored private var scrollContentOrigins: [UUID: CGPoint] = [:]
    /// Scroll content origins snapshotted while a lift is in flight, shifted
    /// uniformly by `scrollableContentDidMove(in:by:)`.
    @ObservationIgnored private var frozenScrollContentOrigins: [UUID: CGPoint]?
    @ObservationIgnored private(set) var sidebarViewports: [UUID: CGRect] = [:]
    @ObservationIgnored private(set) var splitCards: [Key<UUID>: SplitCard] = [:]
    /// What the views of registered rows and zones measured while a lift held
    /// their registrations still, by view, until the lift ends.
    @ObservationIgnored private var heldRows: [UUID: HeldRow] = [:]
    @ObservationIgnored private var heldRowCount = 0
    @ObservationIgnored private var heldZones: [UUID: RegisteredZone] = [:]
    @ObservationIgnored private var heldVirtualRuns: [UUID: VirtualRowRun] = [:]

    /// `space`'s registration of the item, resolved into global coordinates.
    func row(_ id: BrowserSidebarReorderItemID, in space: BrowserSpaceRuntimeAssignment) -> RegisteredRow? {
        if let registered = rows[space]?[id] {
            return resolved(registered)
        }
        if let spaceRuns = virtualRuns[space] {
            for run in spaceRuns.values {
                if let index = run.itemIndexByID[id] {
                    return resolved(
                        RegisteredRow(
                            owner: run.id,
                            row: run.row(at: index),
                            scrollRegionID: run.scrollRegionID,
                            isContentRelative: true
                        )
                    )
                }
            }
        }
        return nil
    }

    /// `space`'s rows, by item, resolved into global coordinates.
    func rows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderItemID: RegisteredRow] {
        var result = (rows[space] ?? [:]).mapValues(resolved)
        if let spaceRuns = virtualRuns[space] {
            for run in spaceRuns.values where run.rowStride > 0 && !run.frame.isEmpty {
                let range = run.visibleIndices.clamped(to: 0..<run.itemIDs.count)
                for index in range {
                    let id = run.itemIDs[index]
                    guard result[id] == nil else { continue }
                    result[id] = resolved(
                        RegisteredRow(
                            owner: run.id,
                            row: run.row(at: index),
                            scrollRegionID: run.scrollRegionID,
                            isContentRelative: true
                        )
                    )
                }
            }
        }
        return result
    }

    /// All registered zones resolved into global coordinates.
    var resolvedZones: [RegisteredZone] {
        zones.values.map(resolved)
    }

    /// Translates `row` into global coordinates when it was measured in its
    /// scroll region's content space.
    func globalRow(
        _ row: BrowserSidebarReorderRow, scrollRegionID: UUID?, isContentRelative: Bool
    ) -> BrowserSidebarReorderRow {
        let offset = contentOrigin(for: scrollRegionID, isContentRelative: isContentRelative)
        guard offset != .zero else { return row }
        return BrowserSidebarReorderRow(
            id: row.id, space: row.space, section: row.section,
            frame: row.frame.offsetBy(dx: offset.x, dy: offset.y),
            parentItemID: row.parentItemID)
    }

    func register(
        row: BrowserSidebarReorderRow, owner: UUID, scrollRegionID: UUID?, isContentRelative: Bool = false
    ) {
        if let previous = rowSpaces[owner], previous != row.space { removeRow(row.id, owner: owner) }
        rowSpaces[owner] = row.space
        let key = Key(id: row.id, space: row.space)
        if let current = rows[row.space]?[row.id] {
            if current.owner == owner, current.row == row, current.scrollRegionID == scrollRegionID,
                current.isContentRelative == isContentRelative
            {
                return
            }
            if current.owner != owner { replacedRows[key, default: [:]][current.owner] = current }
        } else {
            selectionRowsRevision &+= 1
        }
        replacedRows[key]?[owner] = nil
        rows[row.space, default: [:]][row.id] = RegisteredRow(
            owner: owner, row: row, scrollRegionID: scrollRegionID, isContentRelative: isContentRelative)
    }

    /// Keeps what `owner` measured while a lift holds its registration still.
    func hold(
        row: BrowserSidebarReorderRow, owner: UUID, scrollRegionID: UUID?, isContentRelative: Bool = false
    ) {
        heldRowCount &+= 1
        heldRows[owner] = HeldRow(
            order: heldRowCount,
            registration: RegisteredRow(
                owner: owner, row: row, scrollRegionID: scrollRegionID, isContentRelative: isContentRelative))
    }

    /// Registers what views measured while a lift held them still. A drop
    /// that leaves a row where the lift's gap already moved it never moves
    /// that row again, so without this the row would keep the frame it had
    /// before the lift, and the next drag would aim a slot off. They register
    /// in the order the views reported them, as they would have without the
    /// lift, so of two views of one item the later one is in use.
    func registerHeld() {
        let rows = heldRows.values.sorted { $0.order < $1.order }.map(\.registration)
        let zones = heldZones
        let runs = heldVirtualRuns
        heldRows = [:]
        heldZones = [:]
        heldVirtualRuns = [:]
        for held in rows {
            register(
                row: held.row, owner: held.owner, scrollRegionID: held.scrollRegionID,
                isContentRelative: held.isContentRelative)
        }
        for (id, held) in zones { self.zones[id] = held }
        for held in runs.values { register(virtualRun: held) }
    }

    /// Snapshots scroll content origins at the start of a lift so rows stay
    /// frozen in global space unless `scrollableContentDidMove` advances them.
    func freezeScrollOrigins() {
        frozenScrollContentOrigins = scrollContentOrigins
    }

    /// Releases snapshotted scroll origins when a lift ends.
    func unfreezeScrollOrigins() {
        frozenScrollContentOrigins = nil
    }

    func register(scrollContentOrigin origin: CGPoint, for id: UUID) {
        scrollContentOrigins[id] = origin
    }

    /// Forgets `owner`'s registration of the item. When it was the one in
    /// use, the item keeps the registration of a view still showing it in
    /// the same Space, if any.
    func removeRow(_ id: BrowserSidebarReorderItemID, owner: UUID) {
        heldRows[owner] = nil
        guard let space = rowSpaces.removeValue(forKey: owner) else { return }
        let key = Key(id: id, space: space)
        defer { if replacedRows[key]?.isEmpty == true { replacedRows[key] = nil } }
        guard rows[space]?[id]?.owner == owner else {
            replacedRows[key]?[owner] = nil
            return
        }
        if let remaining = replacedRows[key]?.first?.value {
            replacedRows[key]?[remaining.owner] = nil
            rows[space]?[id] = remaining
        } else {
            rows[space]?[id] = nil
            if rows[space]?.isEmpty == true { rows[space] = nil }
            selectionRowsRevision &+= 1
        }
    }

    func hasVirtualRun(for id: UUID, in space: BrowserSpaceRuntimeAssignment) -> Bool {
        virtualRuns[space]?[id] != nil
    }

    func hold(virtualRun run: VirtualRowRun) {
        heldVirtualRuns[run.id] = run
        updateVirtualRunVisibleIndices(run.visibleIndices, for: run.id, in: run.space)
    }

    func register(virtualRun run: VirtualRowRun) {
        heldVirtualRuns[run.id] = nil
        virtualRuns[run.space, default: [:]][run.id] = run
        rowsRevision &+= 1
    }

    func updateVirtualRunVisibleIndices(
        _ visibleIndices: Range<Int>,
        for id: UUID,
        in space: BrowserSpaceRuntimeAssignment
    ) {
        guard virtualRuns[space]?[id]?.visibleIndices != visibleIndices else { return }
        virtualRuns[space]?[id]?.visibleIndices = visibleIndices
    }

    func removeVirtualRun(for id: UUID, in space: BrowserSpaceRuntimeAssignment) {
        heldVirtualRuns[id] = nil
        virtualRuns[space]?[id] = nil
        if virtualRuns[space]?.isEmpty == true { virtualRuns[space] = nil }
        rowsRevision &+= 1
    }

    func registeredRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        var result = (rows[space] ?? [:]).values.map { resolved($0).row }.filter { $0.parentItemID == nil }
        if let spaceRuns = virtualRuns[space] {
            for run in spaceRuns.values where run.rowStride > 0 && !run.frame.isEmpty {
                let range = run.visibleIndices.clamped(to: 0..<run.itemIDs.count)
                result.reserveCapacity(result.count + range.count)
                let offset = contentOrigin(for: run.scrollRegionID, isContentRelative: true)
                for index in range {
                    let row = run.row(at: index)
                    if offset == .zero {
                        result.append(row)
                    } else {
                        result.append(
                            BrowserSidebarReorderRow(
                                id: row.id, space: row.space, section: row.section,
                                frame: row.frame.offsetBy(dx: offset.x, dy: offset.y),
                                parentItemID: nil)
                        )
                    }
                }
            }
        }
        return result
    }

    /// Range selection includes offscreen rows of expanded lists.
    func selectionRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        var result = (rows[space] ?? [:]).values.map { resolved($0).row }.filter { $0.parentItemID == nil }
        if let spaceRuns = virtualRuns[space] {
            for run in spaceRuns.values where run.rowStride > 0 && !run.frame.isEmpty {
                result.reserveCapacity(result.count + run.itemIDs.count)
                let offset = contentOrigin(for: run.scrollRegionID, isContentRelative: true)
                for index in run.itemIDs.indices {
                    let row = run.row(at: index)
                    if offset == .zero {
                        result.append(row)
                    } else {
                        result.append(
                            BrowserSidebarReorderRow(
                                id: row.id, space: row.space, section: row.section,
                                frame: row.frame.offsetBy(dx: offset.x, dy: offset.y),
                                parentItemID: nil)
                        )
                    }
                }
            }
        }
        return result.sorted {
            if $0.usesGridOrdering != $1.usesGridOrdering { return $0.usesGridOrdering }
            if abs($0.frame.minY - $1.frame.minY) > Self.selectionLineTolerance {
                return $0.frame.minY < $1.frame.minY
            }
            return $0.frame.minX < $1.frame.minX
        }
    }

    func register(
        zone: BrowserSidebarReorderZone, for id: UUID, sidebarViewportID: UUID?, scrollRegionID: UUID?,
        isContentRelative: Bool = false
    ) {
        zones[id] = RegisteredZone(
            zone: zone, sidebarViewportID: sidebarViewportID, scrollRegionID: scrollRegionID,
            isContentRelative: isContentRelative)
    }

    /// Keeps what a zone measured while a lift holds its registration still.
    func hold(
        zone: BrowserSidebarReorderZone, for id: UUID, sidebarViewportID: UUID?, scrollRegionID: UUID?,
        isContentRelative: Bool = false
    ) {
        heldZones[id] = RegisteredZone(
            zone: zone, sidebarViewportID: sidebarViewportID, scrollRegionID: scrollRegionID,
            isContentRelative: isContentRelative)
    }

    func register(sidebarViewport frame: CGRect, for id: UUID) { sidebarViewports[id] = frame }

    func removeSidebarViewport(for id: UUID) {
        sidebarViewports[id] = nil
        zones = zones.filter { $0.value.sidebarViewportID != id }
        heldZones = heldZones.filter { $0.value.sidebarViewportID != id }
    }

    func removeZone(for id: UUID) {
        zones[id] = nil
        heldZones[id] = nil
    }

    func register(
        selectionTarget itemID: BrowserSelectionItemID,
        in space: BrowserSpaceRuntimeAssignment,
        frame: CGRect,
        for id: UUID,
        sidebarViewportID: UUID?,
        scrollRegionID: UUID?,
        isContentRelative: Bool = false
    ) {
        selectionTargets[id] = RegisteredSelectionTarget(
            itemID: itemID,
            space: space,
            frame: frame,
            sidebarViewportID: sidebarViewportID,
            scrollRegionID: scrollRegionID,
            isContentRelative: isContentRelative
        )
    }

    func removeSelectionTarget(for id: UUID) {
        selectionTargets[id] = nil
    }

    func setRowSelectionDisabled(
        _ disabled: Bool,
        for itemID: BrowserSidebarReorderItemID,
        in space: BrowserSpaceRuntimeAssignment
    ) {
        if disabled {
            disabledSelectionRows[space, default: []].insert(itemID)
        } else {
            disabledSelectionRows[space]?.remove(itemID)
            if disabledSelectionRows[space]?.isEmpty == true { disabledSelectionRows[space] = nil }
        }
    }

    func setRowAuxiliaryClick(
        _ perform: (@MainActor () -> Void)?,
        for itemID: BrowserSidebarReorderItemID,
        in space: BrowserSpaceRuntimeAssignment
    ) {
        if let perform {
            rowAuxiliaryClickHandlers[space, default: [:]][itemID] = perform
        } else {
            rowAuxiliaryClickHandlers[space]?[itemID] = nil
            if rowAuxiliaryClickHandlers[space]?.isEmpty == true { rowAuxiliaryClickHandlers[space] = nil }
        }
    }

    func selectionItem(
        at globalPoint: CGPoint,
        in space: BrowserSpaceRuntimeAssignment
    ) -> BrowserSelectionItemID? {
        var best: (itemID: BrowserSelectionItemID, area: CGFloat)?
        for target in selectionTargets.values where target.space == space {
            guard !target.frame.isEmpty else { continue }
            guard
                let visibleFrame = visibleGlobalFrame(
                    target.frame,
                    scrollRegionID: target.scrollRegionID,
                    sidebarViewportID: target.sidebarViewportID,
                    isContentRelative: target.isContentRelative
                ), visibleFrame.contains(globalPoint)
            else { continue }
            let area = target.frame.width * target.frame.height
            if best == nil || area < best!.area {
                best = (target.itemID, area)
            }
        }
        let disabled = disabledSelectionRows[space]
        if let spaceRows = rows[space] {
            for registration in spaceRows.values {
                guard case .tab(let tabID) = registration.row.id else { continue }
                if disabled?.contains(registration.row.id) == true { continue }
                guard !registration.row.frame.isEmpty else { continue }
                guard
                    let visibleFrame = visibleGlobalFrame(
                        registration.row.frame,
                        scrollRegionID: registration.scrollRegionID,
                        sidebarViewportID: nil,
                        isContentRelative: registration.isContentRelative
                    ), visibleFrame.contains(globalPoint)
                else { continue }
                let area = registration.row.frame.width * registration.row.frame.height
                if best == nil || area < best!.area {
                    best = (.tab(tabID), area)
                }
            }
        }
        if let spaceRuns = virtualRuns[space] {
            for run in spaceRuns.values where run.rowStride > 0 && !run.frame.isEmpty {
                guard
                    let visibleFrame = visibleGlobalFrame(
                        run.frame,
                        scrollRegionID: run.scrollRegionID,
                        sidebarViewportID: nil,
                        isContentRelative: true
                    ), visibleFrame.contains(globalPoint)
                else { continue }
                let origin = liveContentOrigin(for: run.scrollRegionID, isContentRelative: true)
                let index = Int(floor((globalPoint.y - origin.y - run.frame.minY) / run.rowStride))
                guard run.itemIDs.indices.contains(index),
                    case .tab(let tabID) = run.itemIDs[index],
                    disabled?.contains(run.itemIDs[index]) != true
                else { continue }
                let area = run.frame.width * run.rowStride
                if best == nil || area < best!.area {
                    best = (.tab(tabID), area)
                }
            }
        }
        return best?.itemID
    }

    func auxiliaryClickTarget(
        at globalPoint: CGPoint,
        in space: BrowserSpaceRuntimeAssignment
    ) -> (id: AnyHashable, perform: @MainActor () -> Void)? {
        var best: (id: AnyHashable, area: CGFloat, perform: @MainActor () -> Void)?
        if let spaceRows = rows[space], let handlers = rowAuxiliaryClickHandlers[space] {
            for (itemID, perform) in handlers {
                guard let registration = spaceRows[itemID], !registration.row.frame.isEmpty else { continue }
                guard
                    let visibleFrame = visibleGlobalFrame(
                        registration.row.frame,
                        scrollRegionID: registration.scrollRegionID,
                        sidebarViewportID: nil,
                        isContentRelative: registration.isContentRelative
                    ), visibleFrame.contains(globalPoint)
                else { continue }
                let area = registration.row.frame.width * registration.row.frame.height
                if best == nil || area < best!.area {
                    best = (AnyHashable(itemID), area, perform)
                }
            }
        }
        if let spaceRuns = virtualRuns[space] {
            for run in spaceRuns.values where run.rowStride > 0 && !run.frame.isEmpty {
                guard let handler = run.auxiliaryClick,
                    let visibleFrame = visibleGlobalFrame(
                        run.frame,
                        scrollRegionID: run.scrollRegionID,
                        sidebarViewportID: nil,
                        isContentRelative: true
                    ), visibleFrame.contains(globalPoint)
                else { continue }
                let origin = liveContentOrigin(for: run.scrollRegionID, isContentRelative: true)
                let index = Int(floor((globalPoint.y - origin.y - run.frame.minY) / run.rowStride))
                guard run.itemIDs.indices.contains(index),
                    case .tab(let tabID) = run.itemIDs[index]
                else { continue }
                let area = run.frame.width * run.rowStride
                if best == nil || area < best!.area {
                    best = (AnyHashable(run.itemIDs[index]), area, { handler(tabID) })
                }
            }
        }
        guard let best else { return nil }
        return (best.id, best.perform)
    }

    private func visibleGlobalFrame(
        _ frame: CGRect,
        scrollRegionID: UUID?,
        sidebarViewportID: UUID?,
        isContentRelative: Bool
    ) -> CGRect? {
        let offset = liveContentOrigin(
            for: scrollRegionID,
            isContentRelative: isContentRelative
        )
        var resolved = frame.offsetBy(dx: offset.x, dy: offset.y)
        if let regionID = scrollRegionID {
            guard let viewport = scrollRegions[regionID] else { return nil }
            resolved = resolved.intersection(viewport)
            guard !resolved.isNull, !resolved.isEmpty else { return nil }
        }
        if let viewportID = sidebarViewportID {
            guard let viewport = sidebarViewports[viewportID] else { return nil }
            resolved = resolved.intersection(viewport)
            guard !resolved.isNull, !resolved.isEmpty else { return nil }
        }
        return resolved
    }

    func register(scrollRegionFrame frame: CGRect, for id: UUID) { scrollRegions[id] = frame }

    func removeScrollRegion(for id: UUID) {
        scrollRegions[id] = nil
        scrollContentOrigins[id] = nil
        frozenScrollContentOrigins?[id] = nil
        var removedRows: [UUID] = []
        var removedReplacements: [UUID] = []
        rows = rows.compactMapValues { spaceRows in
            removedRows += spaceRows.values.filter { $0.scrollRegionID == id }.map(\.owner)
            let kept = spaceRows.filter { $0.value.scrollRegionID != id }
            return kept.isEmpty ? nil : kept
        }
        replacedRows = replacedRows.compactMapValues { views in
            removedReplacements += views.values.filter { $0.scrollRegionID == id }.map(\.owner)
            let kept = views.filter { $0.value.scrollRegionID != id }
            return kept.isEmpty ? nil : kept
        }
        for owner in removedRows + removedReplacements { rowSpaces[owner] = nil }
        if !removedRows.isEmpty { selectionRowsRevision &+= 1 }
        zones = zones.filter { $0.value.scrollRegionID != id }
        selectionTargets = selectionTargets.filter { $0.value.scrollRegionID != id }
        heldRows = heldRows.filter { $0.value.registration.scrollRegionID != id }
        heldZones = heldZones.filter { $0.value.scrollRegionID != id }
        heldVirtualRuns = heldVirtualRuns.filter { $0.value.scrollRegionID != id }
        virtualRuns = virtualRuns.compactMapValues { spaceRuns in
            let kept = spaceRuns.filter { $0.value.scrollRegionID != id }
            return kept.isEmpty ? nil : kept
        }
    }

    /// Scrolling translates frozen measurements uniformly during a lift.
    func scrollableContentDidMove(in id: UUID, by offsetY: CGFloat) {
        if let frozen = frozenScrollContentOrigins?[id] {
            frozenScrollContentOrigins?[id] = CGPoint(x: frozen.x, y: frozen.y + offsetY)
            rowsRevision &+= 1
        }
        func moved(_ registration: RegisteredRow) -> RegisteredRow {
            guard !registration.isContentRelative else { return registration }
            var registration = registration
            registration.row = BrowserSidebarReorderRow(
                id: registration.row.id, space: registration.row.space, section: registration.row.section,
                frame: registration.row.frame.offsetBy(dx: 0, dy: offsetY),
                parentItemID: registration.row.parentItemID)
            return registration
        }
        rows = rows.mapValues { spaceRows in
            spaceRows.mapValues { $0.scrollRegionID == id ? moved($0) : $0 }
        }
        replacedRows = replacedRows.mapValues { views in
            views.mapValues { $0.scrollRegionID == id ? moved($0) : $0 }
        }
        for key in Array(zones.keys)
        where zones[key]?.scrollRegionID == id && zones[key]?.isContentRelative == false {
            guard var registration = zones[key] else { continue }
            registration.zone.frame = registration.zone.frame.offsetBy(dx: 0, dy: offsetY)
            zones[key] = registration
        }
    }

    func register(
        splitCardFrame frame: CGRect, for tabID: UUID, in space: BrowserSpaceRuntimeAssignment,
        owner: UUID
    ) {
        splitCards[Key(id: tabID, space: space)] = SplitCard(owner: owner, space: space, frame: frame)
    }

    func removeSplitCardFrame(for tabID: UUID, owner: UUID) {
        for key in splitCards.keys where key.id == tabID && splitCards[key]?.owner == owner {
            splitCards[key] = nil
        }
    }

    func restingZone(for section: BrowserSidebarReorderSection, inColumn frame: CGRect)
        -> BrowserSidebarReorderZone?
    {
        let target = BrowserSidebarReorderZone.Target.section(section)
        let matching = resolvedZones.map(\.zone).filter { zone in
            zone.target == target && zone.frame.maxX > frame.minX && zone.frame.minX < frame.maxX
        }
        return matching.min { $0.frame.height < $1.frame.height }
    }

    private func contentOrigin(for scrollRegionID: UUID?, isContentRelative: Bool) -> CGPoint {
        guard isContentRelative, let scrollRegionID else { return .zero }
        return frozenScrollContentOrigins?[scrollRegionID] ?? scrollContentOrigins[scrollRegionID] ?? .zero
    }

    private func liveContentOrigin(for scrollRegionID: UUID?, isContentRelative: Bool) -> CGPoint {
        guard isContentRelative, let scrollRegionID else { return .zero }
        return scrollContentOrigins[scrollRegionID] ?? .zero
    }

    private func resolved(_ registration: RegisteredRow) -> RegisteredRow {
        let offset = contentOrigin(for: registration.scrollRegionID, isContentRelative: registration.isContentRelative)
        guard offset != .zero else { return registration }
        var resolved = registration
        resolved.row = BrowserSidebarReorderRow(
            id: registration.row.id, space: registration.row.space, section: registration.row.section,
            frame: registration.row.frame.offsetBy(dx: offset.x, dy: offset.y),
            parentItemID: registration.row.parentItemID)
        return resolved
    }

    private func resolved(_ registration: RegisteredZone) -> RegisteredZone {
        let offset = contentOrigin(for: registration.scrollRegionID, isContentRelative: registration.isContentRelative)
        guard offset != .zero else { return registration }
        var resolved = registration
        resolved.zone.frame = registration.zone.frame.offsetBy(dx: offset.x, dy: offset.y)
        return resolved
    }
}
