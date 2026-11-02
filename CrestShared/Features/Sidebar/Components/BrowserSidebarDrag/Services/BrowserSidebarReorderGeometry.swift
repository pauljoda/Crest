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
    }

    struct RegisteredZone {
        var zone: BrowserSidebarReorderZone
        let sidebarViewportID: UUID?
        let scrollRegionID: UUID?
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
    @ObservationIgnored private(set) var scrollRegions: [UUID: CGRect] = [:]
    @ObservationIgnored private(set) var sidebarViewports: [UUID: CGRect] = [:]
    @ObservationIgnored private(set) var splitCards: [Key<UUID>: SplitCard] = [:]

    /// `space`'s registration of the item.
    func row(_ id: BrowserSidebarReorderItemID, in space: BrowserSpaceRuntimeAssignment) -> RegisteredRow? {
        rows[space]?[id]
    }

    /// `space`'s rows, by item.
    func rows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderItemID: RegisteredRow] {
        rows[space] ?? [:]
    }

    func register(row: BrowserSidebarReorderRow, owner: UUID, scrollRegionID: UUID?) {
        if let previous = rowSpaces[owner], previous != row.space { removeRow(row.id, owner: owner) }
        rowSpaces[owner] = row.space
        let key = Key(id: row.id, space: row.space)
        if let current = rows[row.space]?[row.id] {
            if current.owner != owner { replacedRows[key, default: [:]][current.owner] = current }
        } else {
            selectionRowsRevision &+= 1
        }
        replacedRows[key]?[owner] = nil
        rows[row.space, default: [:]][row.id] = RegisteredRow(owner: owner, row: row, scrollRegionID: scrollRegionID)
    }

    /// Forgets `owner`'s registration of the item. When it was the one in
    /// use, the item keeps the registration of a view still showing it in
    /// the same Space, if any.
    func removeRow(_ id: BrowserSidebarReorderItemID, owner: UUID) {
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

    func registeredRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        (rows[space] ?? [:]).values.map(\.row).filter { $0.parentItemID == nil }
    }

    /// Range selection includes offscreen rows of expanded lists.
    func selectionRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        registeredRows(in: space).sorted {
            if $0.usesGridOrdering != $1.usesGridOrdering { return $0.usesGridOrdering }
            if abs($0.frame.minY - $1.frame.minY) > Self.selectionLineTolerance {
                return $0.frame.minY < $1.frame.minY
            }
            return $0.frame.minX < $1.frame.minX
        }
    }

    func register(
        zone: BrowserSidebarReorderZone, for id: UUID, sidebarViewportID: UUID?, scrollRegionID: UUID?
    ) {
        zones[id] = RegisteredZone(
            zone: zone, sidebarViewportID: sidebarViewportID, scrollRegionID: scrollRegionID)
    }

    func register(sidebarViewport frame: CGRect, for id: UUID) { sidebarViewports[id] = frame }

    func removeSidebarViewport(for id: UUID) {
        sidebarViewports[id] = nil
        zones = zones.filter { $0.value.sidebarViewportID != id }
    }

    func removeZone(for id: UUID) { zones[id] = nil }

    func register(scrollRegionFrame frame: CGRect, for id: UUID) { scrollRegions[id] = frame }

    func removeScrollRegion(for id: UUID) {
        scrollRegions[id] = nil
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
    }

    /// Scrolling translates frozen measurements uniformly during a lift.
    func scrollableContentDidMove(in id: UUID, by offsetY: CGFloat) {
        func moved(_ registration: RegisteredRow) -> RegisteredRow {
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
        for key in Array(zones.keys) where zones[key]?.scrollRegionID == id {
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
        let matching = zones.values.map(\.zone).filter { zone in
            zone.target == target && zone.frame.maxX > frame.minX && zone.frame.minX < frame.maxX
        }
        return matching.min { $0.frame.height < $1.frame.height }
    }
}
