import CoreGraphics

/// Resolves where a dragged sidebar item would land, and how far its neighbours
/// step aside to open the gap. Pure geometry so it can be exercised in tests
/// without a live drag.
enum BrowserSidebarReorderPolicy {
    /// A drag must travel this far before it lifts, so a sloppy click still
    /// selects a tab instead of starting a reorder.
    static let liftDistance: CGFloat = 4

    /// Whether the lifted row's pointer-chasing preview is Crest's to draw.
    ///
    /// macOS draws it, in a window-level host ordered above the browser window —
    /// see `BrowserSidebarReorderState.floatingLift` — because anything drawn in
    /// the view tree is clipped by the page, by window chrome, and by every
    /// inset between them. iOS lifts through drag-and-drop, which composites its
    /// own preview under the finger, so there is nothing here to draw and the
    /// row would otherwise appear twice.
    static var drawsOwnLift: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }

    /// How long a row ignores its own activation after being dropped.
    static let activationSuppression: Duration = .milliseconds(250)

    /// Gap the lifted row leaves behind, as a fraction of its own height.
    static let displacementFraction: CGFloat = 1

    /// How far past a section's edge the pointer may stray and still target it.
    /// Sections wrap their rows tightly, so appending to the end of a list means
    /// dragging into the empty space just below the final row.
    static let zoneSlop: CGFloat = 160

    /// Fraction of a collapsed folder's row that nests rather than reorders.
    ///
    /// Dropping onto the middle of the row puts the item inside the folder; the
    /// top and bottom edges belong to the surrounding section, so a row can still
    /// be dragged *past* a collapsed folder instead of always falling into it.
    static let folderNestBand: CGFloat = 0.5

    static func nestingFrame(for frame: CGRect) -> CGRect {
        frame.insetBy(dx: 0, dy: frame.height * (1 - folderNestBand) / 2)
    }

    static func zone(
        at point: CGPoint,
        in zones: [BrowserSidebarReorderZone],
        accepting item: BrowserSidebarReorderItem
    ) -> BrowserSidebarReorderZone? {
        let usable = zones.filter { accepts(item: item, in: $0) }
        let containing = usable.filter { $0.frame.contains(point) }
        if let best = containing.max(by: isLessSpecific) {
            return best
        }
        return nearestSection(to: point, in: usable)
    }

    /// A section only takes its own kind of row. Nested groups register a section
    /// per kind over the same frame, so filtering by acceptance before ranking is
    /// what stops a folder resolving against the tab section it overlaps.
    private static func accepts(
        item: BrowserSidebarReorderItem,
        in zone: BrowserSidebarReorderZone
    ) -> Bool {
        switch zone.target {
        case .section(let section):
            return accepts(item: item, in: section)
        case .folder, .space:
            // A split group moves as one block inside its own Space: it never
            // nests into a folder row and never crosses to another Space in this
            // release. Refusing those zones outright lets the section behind them
            // resolve instead of offering a drop that would do nothing.
            switch item {
            case .tab, .folder: return true
            case .splitGroup: return false
            }
        case .splitContent(let assignment):
            // Only a tab becomes a card. A folder has no page to show, and
            // dragging a whole group into the content area — which would have to
            // mean "present these four instead of those" — is not a gesture this
            // release defines. Splits never span Spaces either, so a tab from
            // elsewhere is refused here rather than relocated first.
            switch item {
            case .tab: return item.spaceAssignment == assignment
            case .folder, .splitGroup: return false
            }
        }
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
    private static func isLessSpecific(
        _ lhs: BrowserSidebarReorderZone,
        _ rhs: BrowserSidebarReorderZone
    ) -> Bool {
        if lhs.specificity != rhs.specificity {
            return lhs.specificity < rhs.specificity
        }
        if lhs.nestingDepth != rhs.nestingDepth {
            return lhs.nestingDepth < rhs.nestingDepth
        }
        return area(of: lhs.frame) > area(of: rhs.frame)
    }

    private static func area(of frame: CGRect) -> CGFloat {
        frame.width * frame.height
    }

    /// Falls back to the closest section in the same column, so overshooting the
    /// bottom of a list still appends to it instead of cancelling the drop.
    private static func nearestSection(
        to point: CGPoint,
        in zones: [BrowserSidebarReorderZone]
    ) -> BrowserSidebarReorderZone? {
        let sections = zones.filter { zone in
            guard case .section = zone.target else { return false }
            return point.x >= zone.frame.minX && point.x <= zone.frame.maxX
        }
        let reachable = sections.compactMap { zone -> (BrowserSidebarReorderZone, CGFloat)? in
            let distance = verticalDistance(from: point, to: zone.frame)
            guard distance <= zoneSlop else { return nil }
            return (zone, distance)
        }
        // Overlapping runs are the same distance away, so the fallback settles
        // the draw exactly as containment would rather than at random.
        return reachable.min { lhs, rhs in
            lhs.1 == rhs.1 ? isLessSpecific(rhs.0, lhs.0) : lhs.1 < rhs.1
        }?.0
    }

    private static func verticalDistance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        if point.y < frame.minY { return frame.minY - point.y }
        if point.y > frame.maxY { return point.y - frame.maxY }
        return 0
    }

    /// Whether a section will take this item at all. Tabs and folders each
    /// reorder only among their own kind, so a folder dragged over the pinned
    /// grid resolves to no target rather than a nonsensical one.
    ///
    /// A split group is a run of tabs and reorders among tabs, but pinned tabs
    /// cannot be members, so the pinned grid refuses it the same way it refuses
    /// a folder.
    static func accepts(
        item: BrowserSidebarReorderItem,
        in section: BrowserSidebarReorderSection
    ) -> Bool {
        switch (item, section) {
        case (.tab, .tabs): true
        case (.splitGroup, .tabs(let placement, _)):
            BrowserSplitGroupPolicy.allowsMembership(placement: placement)
        case (.folder, .folders): true
        default: false
        }
    }

    /// Whether a section has room for a row arriving from elsewhere.
    ///
    /// The pinned grid is capped, and the model refuses a move past the cap. Without
    /// this the drag would show a perfectly good insertion point and then quietly
    /// do nothing on release. Rows already in the section are only reordering, so
    /// they never consume a new slot.
    static func hasRoom(
        for item: BrowserSidebarReorderItem,
        in section: BrowserSidebarReorderSection,
        existingCount: Int,
        isAlreadyInSection: Bool
    ) -> Bool {
        guard case .tabs(placement: .pinned, folderID: _) = section,
            !isAlreadyInSection
        else { return true }
        return existingCount < BrowserSpace.maximumPinnedTabs
    }

    /// Rows belonging to `section`, in their current visual order.
    static func rows(
        in section: BrowserSidebarReorderSection,
        from rows: [BrowserSidebarReorderRow]
    ) -> [BrowserSidebarReorderRow] {
        rows.filter { $0.section == section }.sorted(by: precedes)
    }

    /// Reading order: down the list, and left-to-right within a grid row.
    private static func precedes(
        _ lhs: BrowserSidebarReorderRow,
        _ rhs: BrowserSidebarReorderRow
    ) -> Bool {
        let lhsY = lhs.frame.minY
        let rhsY = rhs.frame.minY
        if lhs.usesGridOrdering, lhsY == rhsY {
            return lhs.frame.minX < rhs.frame.minX
        }
        return lhsY < rhsY
    }

    /// Index the dragged item would occupy within `orderedRows`, excluding
    /// itself. Lists compare against row midpoints; the pinned grid compares
    /// against cell centers so a sideways drag reorders within a row.
    static func insertionIndex(
        at point: CGPoint,
        orderedRows: [BrowserSidebarReorderRow],
        excluding draggedID: BrowserSidebarReorderItemID?
    ) -> Int {
        let candidates = orderedRows.filter { $0.id != draggedID }
        var index = 0
        for row in candidates {
            guard hasPassed(point, row) else { break }
            index += 1
        }
        return index
    }

    /// Whether the pointer has moved beyond a row in reading order.
    ///
    /// A grid cell is only compared horizontally once the pointer is on that
    /// cell's own line; comparing against its center on both axes at once would
    /// treat every cell on the line as passed as soon as the pointer dipped
    /// below the line's middle, which makes leftward moves impossible.
    private static func hasPassed(
        _ point: CGPoint,
        _ row: BrowserSidebarReorderRow
    ) -> Bool {
        guard row.usesGridOrdering else {
            return point.y > row.frame.midY
        }
        if point.y > row.frame.maxY { return true }
        if point.y < row.frame.minY { return false }
        return point.x > row.frame.midX
    }

    /// The row the dragged item should be inserted before, or `nil` to append.
    static func insertionAnchor(
        index: Int,
        orderedRows: [BrowserSidebarReorderRow],
        excluding draggedID: BrowserSidebarReorderItemID?
    ) -> BrowserSidebarReorderItemID? {
        let candidates = orderedRows.filter { $0.id != draggedID }
        guard index < candidates.count else { return nil }
        return candidates[index].id
    }

    /// Geometry of the slots a section lays its rows out in.
    enum SlotLayout: Equatable, Sendable {
        /// One column; rows step vertically by `stride`.
        case list(stride: CGFloat)
        /// Reading-order grid; cells step by `columnStride` across and
        /// `rowStride` down, wrapping every `columns` cells.
        case grid(columns: Int, columnStride: CGFloat, rowStride: CGFloat)
    }

    /// How far a row steps aside to open the gap at `insertionIndex`.
    ///
    /// Rows keep their original layout slots while a drag is in flight — only the
    /// lifted row is offset — so displacement is the difference between the slot
    /// a row currently occupies and the slot it should occupy once the gap is
    /// open. Both are expressed in "list with the lifted row removed" index
    /// space, the same space `insertionIndex` is computed in.
    ///
    /// - Parameters:
    ///   - candidateIndex: the row's index among rows excluding the lifted one.
    ///   - draggedSlot: the lifted row's index in the full, unfiltered list.
    static func displacement(
        candidateIndex: Int,
        draggedSlot: Int,
        insertionIndex: Int,
        layout: SlotLayout
    ) -> CGSize {
        let currentSlot =
            candidateIndex < draggedSlot ? candidateIndex : candidateIndex + 1
        let desiredSlot =
            candidateIndex < insertionIndex ? candidateIndex : candidateIndex + 1
        guard currentSlot != desiredSlot else { return .zero }

        switch layout {
        case .list(let stride):
            let steps = CGFloat(desiredSlot - currentSlot)
            return CGSize(width: 0, height: steps * stride * displacementFraction)
        case .grid(let columns, let columnStride, let rowStride):
            guard columns > 0 else { return .zero }
            let currentColumn = currentSlot % columns
            let currentRow = currentSlot / columns
            let desiredColumn = desiredSlot % columns
            let desiredRow = desiredSlot / columns
            return CGSize(
                width: CGFloat(desiredColumn - currentColumn) * columnStride,
                height: CGFloat(desiredRow - currentRow) * rowStride
            )
        }
    }

    /// Derives slot geometry from the measured rows, so spacing and column count
    /// come from the real layout rather than being duplicated here.
    static func slotLayout(
        for orderedRows: [BrowserSidebarReorderRow],
        fallbackStride: CGFloat
    ) -> SlotLayout {
        let usesGrid = orderedRows.first?.usesGridOrdering ?? false
        guard usesGrid else {
            return .list(stride: stride(ofPitches: verticalPitches(orderedRows), fallback: fallbackStride))
        }

        guard let firstRow = orderedRows.first else {
            return .list(stride: fallbackStride)
        }
        let firstLine = orderedRows.filter { $0.frame.minY == firstRow.frame.minY }
        let columns = max(firstLine.count, 1)
        let columnStride = stride(
            ofPitches: horizontalPitches(firstLine),
            fallback: firstRow.frame.width
        )
        let rowStride = stride(
            ofPitches: verticalPitches(orderedRows),
            fallback: firstRow.frame.height
        )
        return .grid(
            columns: columns,
            columnStride: columnStride,
            rowStride: rowStride
        )
    }

    private static func verticalPitches(
        _ rows: [BrowserSidebarReorderRow]
    ) -> [CGFloat] {
        zip(rows, rows.dropFirst()).map { abs($1.frame.minY - $0.frame.minY) }
    }

    private static func horizontalPitches(
        _ rows: [BrowserSidebarReorderRow]
    ) -> [CGFloat] {
        zip(rows, rows.dropFirst()).map { abs($1.frame.minX - $0.frame.minX) }
    }

    private static func stride(
        ofPitches pitches: [CGFloat],
        fallback: CGFloat
    ) -> CGFloat {
        let positive = pitches.filter { $0 > 0 }
        return positive.min() ?? fallback
    }
}
