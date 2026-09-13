import CoreGraphics
import Foundation
import Observation

/// Coordinates lift lifecycle, landing, and layout projection for one sidebar.
@Observable
@MainActor
final class BrowserSidebarReorderState {
    struct Lift: Equatable, Sendable {
        let item: BrowserSidebarReorderItem
        let section: BrowserSidebarReorderSection
        let rowSize: CGSize
        let grabOffset: CGSize
        var previewRows: [BrowserSidebarReorderRow] = []
    }

    private(set) var lift: Lift?
    private(set) var pointer: CGPoint = .zero
    private(set) var resolvedTarget: BrowserSidebarReorderTarget?
    private(set) var batchConstraintMessage: String?
    var selectionRowsRevision: Int { geometry.selectionRowsRevision }
    @ObservationIgnored var batchValidation: ((BrowserSidebarReorderTarget, BrowserTabBatchRequest) -> String?)?
    private(set) var layout = BrowserSidebarReorderLayout()
    private var lastPreviewShape: BrowserTabDragPreviewShape?
    private(set) var landingPreview: BrowserSidebarFloatingLift?
    private(set) var landingSessionToken: BrowserDragSessionToken?
    @ObservationIgnored private var landingExpirationTask: Task<Void, Never>?
    @ObservationIgnored private var needsLandingMeasurement = false
    @ObservationIgnored private var landingSection: BrowserSidebarReorderSection?

    func isRevealing(_ id: BrowserSidebarReorderItemID) -> Bool {
        landingPreview?.item.selectionRowIDs.contains(id) == true
            && landingPreview?.landing?.isRevealing == true
    }

    func revealLanding(_ id: UUID) {
        guard landingPreview?.landing?.id == id else { return }
        landingPreview?.landing?.isRevealing = true
    }

    func hidesSource(_ id: BrowserSidebarReorderItemID) -> Bool {
        isLifted(id) || landingPreview?.item.selectionRowIDs.contains(id) == true
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

    // Native completion keeps its token when a new measurement replaces the landing ID.
    func finishLanding(session: BrowserDragSessionToken) {
        guard landingSessionToken == session, let id = landingPreview?.landing?.id else { return }
        finishLanding(id)
    }

    @ObservationIgnored private var verticalDirection: CGFloat = 0

    private let geometry = BrowserSidebarReorderGeometry()

    // Staging holds the pager still before native input confirms a moving lift.
    private var stagedLift: (item: BrowserSidebarReorderItem, section: BrowserSidebarReorderSection)?
    @ObservationIgnored private var stagedLiftExpirationTask: Task<Void, Never>?
    @ObservationIgnored private let stagedLiftExpiration: Duration

    init(
        stagedLiftExpiration: Duration = BrowserSidebarReorderPolicy
            .stagedLiftExpiration
    ) {
        self.stagedLiftExpiration = stagedLiftExpiration
    }
    private(set) var isSuppressingActivation = false
    // Latch the content host for the drag so its WebView does not change parents repeatedly.
    private(set) var hasEnteredSplitContent = false
    var suppressesActivation: Bool {
        isDragging || isSuppressingActivation
    }
    @ObservationIgnored private var activationSuppressionTask: Task<Void, Never>?

    var isDragging: Bool { lift != nil }
    var hasLiftInFlight: Bool { lift != nil || stagedLift != nil }

    @ObservationIgnored private var sessionGeneration: UInt64 = 0

    var sessionToken: BrowserDragSessionToken? {
        hasLiftInFlight ? BrowserDragSessionToken(generation: sessionGeneration) : nil
    }

    func isLifted(_ id: BrowserSidebarReorderItemID) -> Bool {
        lift?.item.selectionRowIDs.contains(id) == true
    }

    // MARK: - Geometry registration

    func register(
        row: BrowserSidebarReorderRow,
        owner: UUID,
        scrollRegionID: UUID? = nil
    ) {
        // Freeze transformed rows during a lift; accept newly revealed lazy rows.
        guard !isDragging || geometry.rows[row.id] == nil else { return }
        geometry.register(row: row, owner: owner, scrollRegionID: scrollRegionID)
        if needsLandingMeasurement, var preview = landingPreview, preview.item.id == row.id,
            !row.frame.isEmpty, landingSection == nil || landingSection == row.section,
            preview.landing?.frame != row.frame, preview.landing?.isRevealing != true
        {
            preview.landing = BrowserSidebarReorderLanding(frame: row.frame)
            landingPreview = preview
        }
    }

    func removeRow(_ id: BrowserSidebarReorderItemID, owner: UUID) {
        geometry.removeRow(id, owner: owner)
    }

    private func registeredRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        geometry.registeredRows(in: space)
    }

    func selectionRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        geometry.selectionRows(in: space)
    }

    func register(
        zone: BrowserSidebarReorderZone,
        for id: UUID,
        sidebarViewportID: UUID? = nil,
        scrollRegionID: UUID? = nil
    ) {
        guard !isDragging || geometry.zones[id] == nil else { return }
        geometry.register(
            zone: zone, for: id, sidebarViewportID: sidebarViewportID, scrollRegionID: scrollRegionID)
    }

    func register(sidebarViewport frame: CGRect, for id: UUID) {
        geometry.register(sidebarViewport: frame, for: id)
    }

    func removeSidebarViewport(for id: UUID) { geometry.removeSidebarViewport(for: id) }

    func removeZone(for id: UUID) { geometry.removeZone(for: id) }
    func register(scrollRegionFrame frame: CGRect, for id: UUID) {
        geometry.register(scrollRegionFrame: frame, for: id)
        if isDragging { resolveTarget() }
    }

    func removeScrollRegion(for id: UUID) {
        geometry.removeScrollRegion(for: id)
        if isDragging { resolveTarget() }
    }

    func scrollableContentDidMove(in id: UUID, by offsetY: CGFloat) {
        guard isDragging, offsetY != 0 else { return }
        geometry.scrollableContentDidMove(in: id, by: offsetY)
        refreshLayout()
        resolveTarget()
    }

    private var visibleZones: [BrowserSidebarReorderZone] {
        let pinned = pinnedGeometry
        return geometry.zones.values.compactMap { registration in
            let projected: CGRect?
            if case .section(let section) = registration.zone.target, section.usesGridOrdering,
                let pinned, registration.zone.frame.intersects(pinned.frame)
            {
                projected = CGRect(
                    origin: pinned.frame.origin,
                    size: CGSize(
                        width: pinned.frame.width, height: max(pinned.layout.height, pinned.emptyHeight)))
            } else {
                projected = layout.frame(for: registration.zone)
            }
            guard var frame = projected else { return nil }
            if let regionID = registration.scrollRegionID {
                guard let viewport = geometry.scrollRegions[regionID] else { return nil }
                frame = frame.intersection(viewport)
            }
            if let viewportID = registration.sidebarViewportID {
                guard let viewport = geometry.sidebarViewports[viewportID] else { return nil }
                frame = frame.intersection(viewport)
                guard !frame.isNull, !frame.isEmpty else { return nil }
                if case .section = registration.zone.target {
                    frame.size.width =
                        viewport.maxX + BrowserSidebarReorderPolicy.sidebarExitBuffer - frame.minX
                }
            }
            guard !frame.isNull, !frame.isEmpty else { return nil }
            var zone = registration.zone
            zone.frame = frame
            return zone
        }
    }

    func pinnedLayout(ids: [BrowserSidebarReorderItemID], in space: BrowserSpaceRuntimeAssignment)
        -> BrowserPinnedTabReorderLayout
    {
        guard let lift, lift.item.spaceAssignment == space, case .tab = lift.item else {
            return BrowserPinnedTabReorderLayout(ids: ids)
        }
        var result = BrowserPinnedTabReorderLayout(ids: ids, liftedID: lift.item.id)
        result.liftedIDs = lift.item.selectionRowIDs
        if case .insert(let section, _, let index) = resolvedTarget?.kind, section.usesGridOrdering,
            batchConstraintMessage == nil
        {
            result.insertionIndex = index
        }
        return result
    }

    private var pinnedGeometry: (layout: BrowserPinnedTabReorderLayout, frame: CGRect, emptyHeight: CGFloat)? {
        guard let lift, let source = geometry.rows[lift.item.id]?.row.frame else { return nil }
        let section = BrowserSidebarReorderSection.tabs(placement: .pinned, folderID: nil)
        guard let zone = restingZone(for: section, inColumn: source) else { return nil }
        let ordered = BrowserSidebarReorderPolicy.rows(
            in: section, from: registeredRows(in: lift.item.spaceAssignment))
        let emptyHeight = max(zone.minimumHeight, ordered.isEmpty ? zone.frame.height : 0)
        return (
            pinnedLayout(ids: ordered.map(\.id), in: lift.item.spaceAssignment).applyingPreferences(
                width: zone.frame.width, touch: zone.supportsTouch), zone.frame, emptyHeight
        )
    }

    func register(
        splitCardFrame frame: CGRect,
        for tabID: TabID,
        in space: BrowserSpaceRuntimeAssignment,
        owner: UUID
    ) {
        geometry.register(splitCardFrame: frame, for: tabID, in: space, owner: owner)
    }

    func removeSplitCardFrame(for tabID: TabID, owner: UUID) {
        geometry.removeSplitCardFrame(for: tabID, owner: owner)
    }

    func frame(ofRow id: BrowserSidebarReorderItemID) -> CGRect? {
        geometry.rows[id]?.row.frame
    }

    var orderedSplitCardFrames: [CGRect] {
        BrowserSplitDropPolicy.ordered(geometry.splitCards.values.map(\.frame))
    }

    // MARK: - Drag lifecycle
    func stage(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection
    ) {
        cancel()
        sessionGeneration &+= 1
        stagedLift = (item, section)
        armStagedLiftExpiration()
    }

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
            previewRows: item.selection == nil
                ? folderPreviewRows(for: item)
                : selectionRows(in: item.spaceAssignment).filter { item.selectionRowIDs.contains($0.id) }
        )
        stagedLift = nil
        cancelStagedLiftExpiration()
        hasEnteredSplitContent = false
        verticalDirection = 0
        lastPreviewShape = nil
        self.pointer = pointer
        if let frame {
            layout = BrowserSidebarReorderLayout(
                sourceID: item.id, sourceFrame: frame,
                hiddenIDs: Set(lift?.previewRows.map(\.id) ?? []).union(item.selectionHiddenRowIDs),
                sourceIsGrid: section.usesGridOrdering)
            if item.selection != nil {
                let selectedRows = lift?.previewRows ?? []
                layout.removedFrames = selectedRows.filter { !$0.usesGridOrdering }.map(\.frame)
                layout.batchHeight = selectedRows.reduce(CGFloat.zero) {
                    $0 + ($1.usesGridOrdering ? BrowserTabDragPreviewLayout.rowSize.height : $1.frame.height)
                }
            }
            let ordered = BrowserSidebarReorderPolicy.rows(
                in: section, from: registeredRows(in: item.spaceAssignment))
            let candidates = ordered.filter { !layout.hiddenIDs.contains($0.id) }
            let index = ordered.prefix { $0.id != item.id }.filter { !layout.hiddenIDs.contains($0.id) }
                .count
            resolvedTarget = BrowserSidebarReorderTarget(
                kind: .insert(
                    section: section, beforeID: candidates.dropFirst(index).first?.id, index: index))
            refreshLayout()
            lastPreviewShape = liftTargetShape
        } else {
            resolveTarget()
        }
        validateBatchTarget()
    }

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
        if lift == nil, let staged = stagedLift {
            begin(item: staged.item, section: staged.section, at: pointer)
        }
        guard lift != nil else { return }
        let delta = pointer.y - self.pointer.y
        if abs(delta) > 0.5 { verticalDirection = delta > 0 ? 1 : -1 }
        self.pointer = pointer
        resolveTarget()
    }

    func end(
        retainingPreview: Bool = false, landingTimeout: Duration? = .seconds(1),
        suppressReleaseActivation: Bool = true
    ) -> (
        item: BrowserSidebarReorderItem,
        target: BrowserSidebarReorderTarget
    )? {
        if retainingPreview, batchConstraintMessage == nil, var preview = liftPreview,
            let frame = landingFrame
        {
            preview.landing = BrowserSidebarReorderLanding(frame: frame)
            landingPreview = preview
            landingSessionToken = sessionToken
            needsLandingMeasurement = true
            landingSection = resolvedTarget == nil ? lift?.section : resolvedTarget?.section
            landingExpirationTask?.cancel()
            landingExpirationTask = nil
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
            batchConstraintMessage = nil
            batchValidation = nil
        }
        guard batchConstraintMessage == nil, let lift, let target = resolvedTarget else { return nil }
        return (lift.item, target)
    }

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
        batchConstraintMessage = nil
        batchValidation = nil
    }

    func yieldToCompetingInteraction() {
        cancel()
    }

    func suppressActivation() {
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
    func displacement(for id: BrowserSidebarReorderItemID) -> CGSize {
        if let row = geometry.rows[id]?.row, row.usesGridOrdering,
            row.space == lift?.item.spaceAssignment,
            let pinned = pinnedGeometry, let frame = pinned.layout.frame(for: .tab(id), in: pinned.frame)
        {
            return CGSize(width: frame.minX - row.frame.minX, height: frame.minY - row.frame.minY)
        }
        if layout.isActive, let row = geometry.rows[id]?.row, !row.usesGridOrdering,
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

    func isTargetedFolder(_ folderID: FolderID) -> Bool {
        resolvedTarget?.kind == .intoFolder(folderID)
    }

    // MARK: - Morphing
    var liftTargetShape: BrowserTabDragPreviewShape? {
        guard let lift else { return nil }
        if lift.item.selection != nil, batchConstraintMessage != nil {
            return lift.section.usesGridOrdering ? .pinnedTile : .row
        }
        switch lift.item {
        case .tab:
            break
        case .folder, .splitGroup:
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
            if lastPreviewShape == .pinnedTile { return .pinnedTile }
            guard case .tabs(let placement, _) = lift.section else { return nil }
            return .resting(for: placement)
        }
    }

    var floatingLift: BrowserSidebarFloatingLift? {
        guard BrowserSidebarReorderPolicy.drawsOwnLift else { return nil }
        return liftPreview
    }

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
            sidebarBounds: pinned?.frame,
            constraintMessage: batchConstraintMessage
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
            return geometry.rows[.folder(id)].flatMap { layout.frame(for: $0.row) }
        case .createCurrentFolder(let id):
            return geometry.rows[.tab(id)].flatMap { layout.frame(for: $0.row) }
        case .none:
            return geometry.rows[lift.item.id]?.row.frame
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
            validateBatchTarget()
            if resolvedTarget != previousTarget { refreshLayout() }
            if resolvedTarget != nil { lastPreviewShape = liftTargetShape }
        }
        guard let lift else {
            resolvedTarget = nil
            return
        }
        resolvedTarget = BrowserSidebarReorderTargetResolver(
            lift: lift, pointer: pointer, insertionPoint: insertionProbe(for: lift), layout: layout,
            pinned: pinnedGeometry, zones: visibleZones, rows: geometry.rows,
            splitCards: geometry.splitCards
        ).resolve(previousTarget: previousTarget)
        if case .splitInsert = resolvedTarget?.kind { hasEnteredSplitContent = true }
    }

    private func validateBatchTarget() {
        guard let request = lift?.item.selection, let target = resolvedTarget else {
            batchConstraintMessage = nil
            return
        }
        batchConstraintMessage = batchValidation?(target, request)
    }

    // Tall blocks cross neighbours with their moving edge rather than the grabbed header.
    private func insertionProbe(for lift: Lift) -> CGPoint {
        guard layout.isActive,
            lift.rowSize.height > BrowserSidebarReorderPolicy.movingEdgeProbeMinimumHeight,
            verticalDirection != 0
        else { return pointer }
        let top = pointer.y - lift.grabOffset.height
        return CGPoint(x: pointer.x, y: verticalDirection > 0 ? top + lift.rowSize.height : top)
    }

    private func refreshLayout() {
        guard let lift, layout.isActive else { return }
        var next = layout
        next.sourceFrame = geometry.rows[lift.item.id]?.row.frame ?? layout.sourceFrame
        if let pinned = pinnedGeometry {
            next.gridFrame = pinned.frame
            next.gridHeightDelta =
                lift.section.usesGridOrdering || resolvedTarget?.section?.usesGridOrdering == true
                ? max(pinned.emptyHeight, pinned.layout.height) - pinned.frame.height : 0
        }
        next.gap = nil
        if batchConstraintMessage != nil {
            if next != layout { layout = next }
            return
        }
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
                parent = geometry.rows[.folder(id)]?.row.section.parentFolderID
            }
            next.gap = BrowserSidebarReorderLayout.Gap(
                section: section, anchor: anchor, frame: frame, containingFolders: parents)
        }
        if next != layout { layout = next }
    }

    private func restingZone(for section: BrowserSidebarReorderSection, inColumn frame: CGRect)
        -> BrowserSidebarReorderZone?
    {
        geometry.restingZone(for: section, inColumn: frame)
    }

}
