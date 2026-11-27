import CoreGraphics
import Foundation

/// A measured region that can accept a lifted sidebar item. Zones are ranked by
/// specificity so a folder header or space segment layered inside a section wins
/// over the section behind it.
struct BrowserSidebarReorderZone: Equatable, Sendable {
    // MARK: - Types

    /// Self-describing destination for a measured sidebar drop zone. Each kind
    /// carries its own specificity, acceptance, projection and landing behavior
    /// rather than switching on a case tag.
    struct Target: Hashable, Sendable {
        // MARK: - Types

        private enum Identity: Hashable, Sendable {
            case section(BrowserSidebarReorderSection)
            case folder(UUID)
            case currentTab(UUID)
            case space(BrowserSpaceRuntimeAssignment)
            case splitContent(BrowserSpaceRuntimeAssignment)
        }

        // MARK: - Variables

        private let identity: Identity
        /// The ordered run when this target is a section, or nil for leaf targets.
        let section: BrowserSidebarReorderSection?
        /// Higher wins when zones overlap.
        let specificity: Int
        /// Whether the target files what lands on it inside its own row: a
        /// collapsed folder, or an open tab a folder is made around. It claims
        /// only the middle of its row, so the edges stay available for
        /// reordering past it, and it wins over the section behind it.
        let nests: Bool
        /// Whether a lift over the target lands there even where an open gap
        /// would hold it in place. A Space picker remains reachable when a tall
        /// batch's temporary gap overlaps it or the lifted folder's moving edge
        /// extends beyond it.
        let outranksGap: Bool
        /// Whether this is the window's content area — the one zone a sidebar can
        /// be drawn on top of, and the only one whose frame says nothing about what
        /// the pointer is aiming at while it is.
        let isContentArea: Bool
        /// Breaks ties between zones of equal specificity: a run nested inside
        /// another wins even when the two measure the same rectangle. Only sections
        /// nest; every other target is a leaf.
        let nestingDepth: Int
        private let checkOffered: @Sendable (DropTargetList) -> Bool
        private let checkAccepts: @Sendable (BrowserSidebarReorderItem) -> Bool
        private let resolveReorderTarget:
            @MainActor @Sendable (BrowserSidebarReorderAim) -> BrowserSidebarReorderTarget?
        private let projectFrame: @Sendable (CGRect, BrowserSidebarReorderLayout) -> CGRect?
        private let resolveAimingFrame: @Sendable (CGRect) -> CGRect

        // MARK: - Actions - Factories

        /// An ordered run of rows.
        static func section(_ section: BrowserSidebarReorderSection) -> Self {
            Self(
                identity: .section(section),
                section: section,
                specificity: 1,
                nests: false,
                outranksGap: false,
                isContentArea: false,
                nestingDepth: section.nestingDepth,
                checkOffered: { targets in section.isOffered(by: targets) },
                checkAccepts: { item in item.isAccepted(by: section) },
                resolveReorderTarget: { aim in aim.insertionTarget(in: section) },
                projectFrame: { frame, layout in
                    guard !section.usesGridOrdering else { return frame }
                    if let parent = section.parentFolderID, layout.hiddenIDs.contains(.folder(parent)) { return nil }
                    return layout.projected(frame, containsGap: layout.holdsGap(section, at: frame))
                },
                resolveAimingFrame: { frame in
                    guard section.parentFolderID != nil else { return frame }
                    return frame.insetBy(dx: 0, dy: min(8, frame.height / 4))
                }
            )
        }

        /// A collapsed folder row: dropping lands the item inside the folder.
        static func folder(_ folderID: UUID) -> Self {
            Self(
                identity: .folder(folderID),
                section: nil,
                specificity: 2,
                nests: true,
                outranksGap: false,
                isContentArea: false,
                nestingDepth: 0,
                checkOffered: { targets in targets.lists.contains { $0.folderID == folderID } },
                checkAccepts: { _ in true },
                resolveReorderTarget: { aim in
                    aim.lift.item.id == .folder(folderID)
                        ? nil : BrowserSidebarReorderTarget(kind: .intoFolder(folderID))
                },
                projectFrame: { frame, layout in
                    guard !layout.hiddenIDs.contains(.folder(folderID)) else { return nil }
                    return layout.projected(frame, containsGap: false)
                },
                resolveAimingFrame: { $0 }
            )
        }

        /// An open tab at the top level: dropping makes a folder around it.
        static func currentTab(_ tabID: UUID) -> Self {
            Self(
                identity: .currentTab(tabID),
                section: nil,
                specificity: 2,
                nests: true,
                outranksGap: false,
                isContentArea: false,
                nestingDepth: 0,
                checkOffered: { targets in targets.folderAroundTabIDs.contains(tabID) },
                checkAccepts: { item in item.foldsAround(tabID) },
                resolveReorderTarget: { _ in BrowserSidebarReorderTarget(kind: .createCurrentFolder(tabID)) },
                projectFrame: { frame, layout in
                    guard !layout.hiddenIDs.contains(.tab(tabID)) else { return nil }
                    return layout.projected(frame, containsGap: false)
                },
                resolveAimingFrame: { $0 }
            )
        }

        /// A space picker segment: dropping moves the item to that space.
        static func space(_ assignment: BrowserSpaceRuntimeAssignment) -> Self {
            Self(
                identity: .space(assignment),
                section: nil,
                specificity: 3,
                nests: false,
                outranksGap: true,
                isContentArea: false,
                nestingDepth: 0,
                checkOffered: { targets in targets.spaceIDs.contains(assignment.spaceID) },
                checkAccepts: { _ in true },
                resolveReorderTarget: { _ in BrowserSidebarReorderTarget(kind: .space(assignment)) },
                projectFrame: { frame, _ in frame },
                resolveAimingFrame: { $0 }
            )
        }

        /// The window's web-content area for a Space: dropping a tab there adds
        /// it to the cards already on show.
        static func splitContent(_ assignment: BrowserSpaceRuntimeAssignment) -> Self {
            Self(
                identity: .splitContent(assignment),
                section: nil,
                specificity: 0,
                nests: false,
                outranksGap: false,
                isContentArea: true,
                nestingDepth: 0,
                checkOffered: { targets in targets.split.map { $0.refusal == nil } ?? false },
                checkAccepts: { item in item.joinsCards(shownIn: assignment) },
                resolveReorderTarget: { aim in aim.splitInsertTarget(in: assignment) },
                projectFrame: { frame, _ in frame },
                resolveAimingFrame: { $0 }
            )
        }

        // MARK: - Actions - Offers

        /// Whether the core lists a drop on this target among `targets`,
        /// refused or not.
        func isOffered(by targets: DropTargetList) -> Bool {
            checkOffered(targets)
        }

        /// Whether the target takes `item` at all. A section only takes its own
        /// kind of row. Nested groups register a section per kind over the same
        /// frame, so filtering by acceptance before ranking is what stops a
        /// folder resolving against the tab section it overlaps.
        func accepts(_ item: BrowserSidebarReorderItem) -> Bool {
            checkAccepts(item)
        }

        // MARK: - Actions - Landing

        /// Where a lift aimed at this target lands, as `aim` reads the
        /// rows and cards around it, or nil where it lands nowhere.
        @MainActor
        func reorderTarget(for aim: BrowserSidebarReorderAim) -> BrowserSidebarReorderTarget? {
            resolveReorderTarget(aim)
        }

        /// Where the target measured at `frame` stands in `layout` while a
        /// lift is in flight, or nil while the lift hides it.
        func frame(_ frame: CGRect, in layout: BrowserSidebarReorderLayout) -> CGRect? {
            projectFrame(frame, layout)
        }

        /// The frame that owns the pointer. A folder owns its contents, while its
        /// outer edge belongs to its parent. This makes a seam between siblings
        /// usable.
        func aimingFrame(for frame: CGRect) -> CGRect {
            resolveAimingFrame(frame)
        }

        // MARK: - Actions - Equality

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.identity == rhs.identity
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(identity)
        }
    }

    // MARK: - Static Variables

    /// How far past a section's edge the pointer may stray and still target it.
    /// Sections wrap their rows tightly, so appending to the end of a list means
    /// dragging into the empty space just below the final row.
    static let slop: CGFloat = 160

    /// Fraction of a collapsed folder's row that nests rather than reorders.
    ///
    /// Dropping onto the middle of the row puts the item inside the folder; the
    /// top and bottom edges belong to the surrounding section, so a row can still
    /// be dragged *past* a collapsed folder instead of always falling into it.
    static let folderNestBand: CGFloat = 0.5

    // MARK: - Variables

    let target: Target
    var frame: CGRect
    var minimumHeight: CGFloat = 0
    var supportsTouch = false

    /// Higher wins when zones overlap.
    var specificity: Int { target.specificity }

    /// Whether this is the window's content area — the one zone a sidebar can be
    /// drawn on top of, and the only one whose frame says nothing about what the
    /// pointer is aiming at while it is.
    var isContentArea: Bool { target.isContentArea }

    /// Breaks ties between zones of equal specificity: a run nested inside
    /// another wins even when the two measure the same rectangle. Only sections
    /// nest; every other target is a leaf.
    var nestingDepth: Int { target.nestingDepth }

    private var area: CGFloat {
        frame.width * frame.height
    }

    private var aimingFrame: CGRect {
        target.aimingFrame(for: frame)
    }

    // MARK: - Actions - Aiming

    /// The middle of a row a nesting target claims, leaving its edges to the
    /// section around it.
    static func nestingFrame(for frame: CGRect) -> CGRect {
        frame.insetBy(dx: 0, dy: frame.height * (1 - folderNestBand) / 2)
    }

    /// The zone the pointer aims `item` at. Only zones the item's kind takes
    /// compete, and of those, only the ones the lift's plan says the core
    /// offers a drop for, so a target the core has no drop for never hides
    /// the section behind it.
    static func aimed(
        at point: CGPoint,
        in zones: [BrowserSidebarReorderZone],
        accepting item: BrowserSidebarReorderItem,
        plan: BrowserSidebarLiftPlan? = nil
    ) -> BrowserSidebarReorderZone? {
        let usable = zones.filter { $0.target.accepts(item) && plan?.offers($0.target) != false }
        let containing = usable.filter { $0.aimingFrame.contains(point) }
        let innermost = containing.max { $0.isLessSpecific(than: $1) }
        if let innermost, !innermost.isContentArea {
            return innermost
        }
        // Containing the pointer is not enough for the content area to own it.
        // A floating sidebar is drawn on top of that zone, so the whole card —
        // including every seam its own layout leaves between the runs, and the
        // furniture above them — sits inside it. Ranking by specificity alone
        // hands those seams to the page: the pinned grid stops being reachable
        // from anywhere but its exact rectangle, which for a grid nobody has
        // filled is a band a few points tall, and a drag that the content area
        // then declines resolves nowhere at all.
        //
        // So a run the pointer is aiming at is offered first, on the same terms
        // as anywhere else in the sidebar — its own column, within the slop that
        // lets a list be appended to. Past the sidebar no run answers, and the
        // page is what is left.
        return nearestSection(to: point, in: usable) ?? innermost
    }

    /// Falls back to the closest section in the same column, so overshooting the
    /// bottom of a list still appends to it instead of cancelling the drop.
    private static func nearestSection(
        to point: CGPoint,
        in zones: [BrowserSidebarReorderZone]
    ) -> BrowserSidebarReorderZone? {
        let sections = zones.filter { zone in
            zone.target.section != nil && point.x >= zone.frame.minX && point.x <= zone.frame.maxX
        }
        let reachable = sections.compactMap { zone -> (BrowserSidebarReorderZone, CGFloat)? in
            let distance = zone.verticalDistance(from: point)
            guard distance <= slop else { return nil }
            return (zone, distance)
        }
        // Overlapping runs are the same distance away, so the fallback settles
        // the draw exactly as containment would rather than at random.
        return reachable.min { lhs, rhs in
            lhs.1 == rhs.1 ? rhs.0.isLessSpecific(than: lhs.0) : lhs.1 < rhs.1
        }?.0
    }

    /// Ranks overlapping zones: more specific first, then the more deeply
    /// nested, then the innermost, so a nested folder group wins over the
    /// section that contains it.
    ///
    /// Nesting is ranked before area because the two are not the same question.
    /// A saved list holding one folder and no unfiled rows measures exactly what
    /// the folder group measures, which leaves area a tie — and a tie is settled
    /// by whichever registration the registry happens to yield first, so the
    /// list can end up owning the rows nested inside it. Those rows then belong
    /// to a section with nothing registered in it: no step-aside, no insertion
    /// line, and a drop that quietly unfiles the tab.
    private func isLessSpecific(than other: BrowserSidebarReorderZone) -> Bool {
        if specificity != other.specificity {
            return specificity < other.specificity
        }
        if nestingDepth != other.nestingDepth {
            return nestingDepth < other.nestingDepth
        }
        return area > other.area
    }

    private func verticalDistance(from point: CGPoint) -> CGFloat {
        if point.y < frame.minY { return frame.minY - point.y }
        if point.y > frame.maxY { return point.y - frame.maxY }
        return 0
    }
}
