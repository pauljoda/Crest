import CoreGraphics
import Foundation
import Observation

/// Resting measurements for one window; registrations retain their view owner.
@Observable
@MainActor
final class BrowserSidebarReorderGeometry {
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

    private(set) var selectionRowsRevision = 0
    @ObservationIgnored private(set) var rows: [BrowserSidebarReorderItemID: RegisteredRow] = [:]
    @ObservationIgnored private(set) var zones: [UUID: RegisteredZone] = [:]
    @ObservationIgnored private(set) var scrollRegions: [UUID: CGRect] = [:]
    @ObservationIgnored private(set) var sidebarViewports: [UUID: CGRect] = [:]
    @ObservationIgnored private(set) var splitCards: [TabID: SplitCard] = [:]

    func register(row: BrowserSidebarReorderRow, owner: UUID, scrollRegionID: UUID?) {
        if rows[row.id] == nil { selectionRowsRevision &+= 1 }
        rows[row.id] = RegisteredRow(owner: owner, row: row, scrollRegionID: scrollRegionID)
    }

    func removeRow(_ id: BrowserSidebarReorderItemID, owner: UUID) {
        guard rows[id]?.owner == owner else { return }
        rows[id] = nil
        selectionRowsRevision &+= 1
    }

    func registeredRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        rows.values.map(\.row).filter { $0.space == space }
    }

    /// Range selection includes offscreen rows of expanded lists.
    func selectionRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        registeredRows(in: space).sorted {
            if $0.usesGridOrdering != $1.usesGridOrdering { return $0.usesGridOrdering }
            if abs($0.frame.minY - $1.frame.minY) > BrowserSidebarReorderPolicy.selectionLineTolerance {
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
        let previousCount = rows.count
        rows = rows.filter { $0.value.scrollRegionID != id }
        if rows.count != previousCount { selectionRowsRevision &+= 1 }
        zones = zones.filter { $0.value.scrollRegionID != id }
    }

    /// Scrolling translates frozen measurements uniformly during a lift.
    func scrollableContentDidMove(in id: UUID, by offsetY: CGFloat) {
        for key in Array(rows.keys) where rows[key]?.scrollRegionID == id {
            guard var registration = rows[key] else { continue }
            registration.row = BrowserSidebarReorderRow(
                id: registration.row.id, space: registration.row.space, section: registration.row.section,
                frame: registration.row.frame.offsetBy(dx: 0, dy: offsetY))
            rows[key] = registration
        }
        for key in Array(zones.keys) where zones[key]?.scrollRegionID == id {
            guard var registration = zones[key] else { continue }
            registration.zone.frame = registration.zone.frame.offsetBy(dx: 0, dy: offsetY)
            zones[key] = registration
        }
    }

    func register(
        splitCardFrame frame: CGRect, for tabID: TabID, in space: BrowserSpaceRuntimeAssignment,
        owner: UUID
    ) {
        splitCards[tabID] = SplitCard(owner: owner, space: space, frame: frame)
    }

    func removeSplitCardFrame(for tabID: TabID, owner: UUID) {
        guard splitCards[tabID]?.owner == owner else { return }
        splitCards[tabID] = nil
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
