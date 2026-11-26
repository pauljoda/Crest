import SwiftUI

/// The rows of one list the core publishes, on every shell: the top level of
/// a section or the inside of a folder.
///
/// It reads only that list and the objects its rows stand for, and hands each
/// row its objects, so a move redraws only the list it moves within, a new
/// title or icon redraws only its own row, and showing another tab redraws no
/// list.
///
/// Tab rows are made only as they scroll into view, in runs between the
/// folders and splits, which are made with the list. A lazy stack places the
/// rows it has not made yet from the ones it has, and tab rows share one
/// height, so those places are right and the list settles in one pass. A
/// folder is as tall as everything open inside it, and a split as its members:
/// in a lazy stack, each one it made moved the rows it had not, which moved
/// what was on screen and what it had to make next, and the sidebar could lay
/// itself out again and again without ever settling.
///
/// A folder's list can hold folders far below its first screen, each with all
/// it holds made with the list. Where the list asks for it, a folder that
/// many rows down draws what it holds only once the list has opened, one
/// folder at a time, so opening a long folder makes what shows first.
struct BrowserSidebarListRows<Trailing: View>: View {
    // MARK: - Types

    /// A stretch of the list laid out one way: the tab rows between two
    /// folders or splits, made as they scroll into view, or one folder or
    /// split, made with the list.
    struct Run: Identifiable {
        enum ID: Hashable {
            /// The tab rows after the item, or at the top of the list. A run
            /// keeps its identity while tabs come and go at its top.
            case tabs(after: BrowserSidebarReorderItemID?)
            case item(BrowserSidebarReorderItemID)
        }

        let id: ID
        var items: [BrowserSidebarListItem]

        var isLazy: Bool {
            if case .tabs = id { true } else { false }
        }

        /// The list's items as runs, in order.
        static func runs(of items: [BrowserSidebarListItem]) -> [Run] {
            var runs: [Run] = []
            for item in items {
                guard item.isTabRow else {
                    runs.append(Run(id: .item(item.id), items: [item]))
                    continue
                }
                if let last = runs.indices.last, runs[last].isLazy {
                    runs[last].items.append(item)
                } else {
                    runs.append(Run(id: .tabs(after: runs.last?.items.last?.id), items: [item]))
                }
            }
            return runs
        }
    }

    // MARK: - Static Variables

    /// How many rows down a list a folder starts before it waits to draw what
    /// it holds: past the first screen on every shell. Only the list's own
    /// rows count, a folder as one, so a folder is never held back while it
    /// could be on screen.
    private static var deferredFolderDistance: Int { 40 }

    /// Minimum tab count in a fixed-height lazy run before switching from a
    /// `LazyVStack` to a fixed-pool recycled run, eliminating per-row view
    /// creation and teardown during fast flicks and long jumps.
    private static var recycledRunMinimumCount: Int { 40 }

    // MARK: - Variables

    let list: SidebarListModel
    let context: BrowserSidebarListContext
    /// The tabs a collapsed folder around the list keeps on screen, which
    /// shows only the rows that hold one, or nil for every row.
    var keptTabIDs: Set<UUID>? = nil
    /// Whether a folder far down the list waits to draw what it holds until
    /// the list has opened, as a folder's own list does.
    var defersDistantFolders = false
    /// What the list shows after its rows, given the rows it holds, such as
    /// the band an empty run keeps.
    @ViewBuilder var trailing: ([BrowserSidebarListItem]) -> Trailing

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction: BrowserSidebarInteractionState?
    @Environment(\.browserSidebarVisibleBand) private var visibleBand
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var fixedTabRowStride: CGFloat? {
        guard context.capabilities.tabRowMetrics.fillsRowHeight else { return nil }
        let appearance = BrowserDeviceAppearanceStore.shared
        let rowHeight = context.capabilities.tabRowHeight(
            tabScale: appearance.tabScale,
            dynamicTypeSize: dynamicTypeSize
        )
        let separation = BrowserSidebarDensity.current.rowSeparation(
            hasBorders: appearance.tabs.borders == .all
        )
        return rowHeight + separation
    }

    var body: some View {
        let items = BrowserSidebarListItem.items(of: list, in: context.space).filter(isShown)
        let deferrals = defersDistantFolders && keptTabIDs == nil ? Self.deferredFolders(of: items) : []
        let rowStride = fixedTabRowStride
        let lazyStackRowStride =
            sidebarInteraction?.sidebarReorderState.layout.isActive == true ? nil : rowStride
        VStack(spacing: 0) {
            ForEach(Run.runs(of: items)) { run in
                if run.isLazy {
                    if let rowStride, let visibleBand, !isVoiceOverEnabled, !isSwitchControlEnabled,
                        run.items.count > Self.recycledRunMinimumCount
                    {
                        BrowserSidebarRecycledTabRun(
                            items: run.items,
                            itemsRevision: UUID(),
                            rowStride: rowStride,
                            context: context,
                            visibleBand: visibleBand
                        )
                    } else {
                        LazyVStack(spacing: 0) { rows(run.items, deferrals: deferrals) }
                            .frame(
                                height: lazyStackRowStride.map { CGFloat(run.items.count) * $0 },
                                alignment: .top
                            )
                    }
                } else {
                    rows(run.items, deferrals: deferrals)
                }
            }
            trailing(items)
        }
        .crestCollectionMotion(ids: items.map(\.collectionMotionID))
        .environment(\.browserInteractionCapabilities, context.capabilities)
    }

    // MARK: - Actions - Rows

    private func rows(
        _ items: [BrowserSidebarListItem], deferrals: Set<BrowserSidebarReorderItemID>
    ) -> some View {
        ForEach(items) { item in
            BrowserSidebarListRow(
                item: item, context: context, keptTabIDs: keptTabIDs, defersContents: deferrals.contains(item.id)
            )
            .equatable()
        }
    }

    /// The folders at least `deferredFolderDistance` rows down `items`, which
    /// draw what they hold only once the list has opened.
    private static func deferredFolders(of items: [BrowserSidebarListItem]) -> Set<BrowserSidebarReorderItemID> {
        var rows = 0
        var deferred: Set<BrowserSidebarReorderItemID> = []
        for item in items {
            switch item.content {
            case .tab: rows += 1
            case .split(_, let members): rows += members.count + 1
            case .folder:
                if rows >= deferredFolderDistance { deferred.insert(item.id) }
                rows += 1
            }
        }
        return deferred
    }

    /// Whether `item` shows: every row of an open list, and of a kept one
    /// the rows that hold a kept tab, the tab itself, its split, or a folder
    /// on the way to it.
    private func isShown(_ item: BrowserSidebarListItem) -> Bool {
        guard let keptTabIDs else { return true }
        return keptTabIDs.contains { item.content.contains(tabID: $0, in: context.space) }
    }
}

extension BrowserSidebarListRows: @MainActor Equatable {
    /// Rows views are equal when they draw the same list for the same Space and
    /// window, as SwiftUI compares a view's inputs, so a section that redraws
    /// leaves its list alone. What trails the rows depends only on those.
    static func == (lhs: BrowserSidebarListRows, rhs: BrowserSidebarListRows) -> Bool {
        lhs.list === rhs.list && lhs.context == rhs.context && lhs.keptTabIDs == rhs.keptTabIDs
            && lhs.defersDistantFolders == rhs.defersDistantFolders
    }
}

extension BrowserSidebarListRows where Trailing == EmptyView {
    init(list: SidebarListModel, context: BrowserSidebarListContext, keptTabIDs: Set<UUID>? = nil) {
        self.init(list: list, context: context, keptTabIDs: keptTabIDs) { _ in EmptyView() }
    }
}

/// One row of a sidebar list: a tab, a split, or a folder with what it holds,
/// indented to the folders around it.
struct BrowserSidebarListRow: View {
    // MARK: - Variables

    let item: BrowserSidebarListItem
    let context: BrowserSidebarListContext
    /// The tabs a collapsed folder around the row keeps on screen, which a
    /// folder row shows the way to in place of its contents.
    var keptTabIDs: Set<UUID>? = nil
    /// Whether a folder far down a list that has just opened waits to draw
    /// what it holds. A folder already drawn keeps what it shows.
    var defersContents = false

    var body: some View {
        content.environment(\.sidebarLayerDepth, item.depth)
    }

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case .tab(let tab):
            BrowserSidebarTabRow(tab: tab, context: context)
                .equatable()
                .modifier(BrowserSidebarFolderRowIndent(depth: item.depth))
                #if os(macOS)
                    // Resolve collection movement once for the whole row,
                    // including native controls and SwiftUI drawing layers.
                    .geometryGroup()
                #endif
                // Keep the identity used when revealing the shown tab.
                .id(tab.id)
        case .split(let groupID, let members):
            BrowserSidebarSplitGroupRow(groupID: groupID, members: members, context: context)
                .equatable()
                .modifier(BrowserSidebarFolderRowIndent(depth: item.depth))
                #if os(macOS)
                    .geometryGroup()
                #endif
        case .folder(let folder):
            BrowserFolderGroup(
                folder: folder, depth: item.depth, context: context, inheritedKeptTabIDs: keptTabIDs,
                defersContents: defersContents
            )
            .equatable()
            .padding(.trailing, item.depth > 0 ? BrowserFolderLayout.nestingIndent : 0)
            .modifier(
                BrowserFolderOffscreenPlaceholder(folder: folder, context: context, isEnabled: keptTabIDs == nil)
            )
            .crestCollectionItemTransition()
        }
    }
}

extension BrowserSidebarListRow: @MainActor Equatable {
    /// Rows are equal when they stand for the same objects in the same place,
    /// as SwiftUI compares a view's inputs, so a list that redraws leaves every
    /// unchanged row alone. A folder's deferral counts only as it is first
    /// drawn, so it leaves the row alone too.
    static func == (lhs: BrowserSidebarListRow, rhs: BrowserSidebarListRow) -> Bool {
        lhs.item == rhs.item && lhs.context == rhs.context && lhs.keptTabIDs == rhs.keptTabIDs
    }
}

/// Steps a row inside a folder in by the folders around it: its surface by
/// the folders' padding, and its icon and title past the folder's own. A row
/// at a section's top level stays put. Rows inside a folder stack as they do
/// at the top level; the folder's padding is what holds them off its edges.
private struct BrowserSidebarFolderRowIndent: ViewModifier {
    let depth: Int

    @Environment(\.sidebarFolderRowTransition) private var transition

    @ViewBuilder
    func body(content: Content) -> some View {
        if depth > 0 {
            content
                .environment(\.sidebarRowContentIndent, BrowserFolderLayout.rowContentIndent(depth: depth))
                .padding(.leading, BrowserFolderLayout.rowLeadingInset(depth: depth - 1))
                .padding(.trailing, BrowserFolderLayout.nestingIndent)
                .frame(maxWidth: .infinity)
                // The innermost transition is the one a row uses, so a row
                // that comes and goes its own way says so here.
                .transition(transition ?? .opacity.combined(with: .move(edge: .top)))
        } else {
            content
        }
    }
}

/// Renders a long fixed-height run of tab rows with a fixed ring of recycled
/// SwiftUI view slots rather than creating and tearing down row subgraphs as
/// tabs enter and leave the viewport.
private struct BrowserSidebarRecycledTabRun: View {
    private struct DragProjection {
        let isActive: Bool
        let liftedIndices: [Int]
        let liftOwnerIndex: Int?
        let gapAnchorIndex: Int?
        let gapInsertsBeforeAnchor: Bool
        let gapHeight: CGFloat

        static let idle = DragProjection(
            isActive: false,
            liftedIndices: [],
            liftOwnerIndex: nil,
            gapAnchorIndex: nil,
            gapInsertsBeforeAnchor: false,
            gapHeight: 0
        )

        func totalHeight(itemCount: Int, rowStride: CGFloat) -> CGFloat {
            guard isActive else { return CGFloat(itemCount) * rowStride }
            let remaining = max(0, itemCount - liftedIndices.count)
            return CGFloat(remaining) * rowStride + (gapAnchorIndex != nil ? gapHeight : 0)
        }

        func yOffset(for index: Int, rowStride: CGFloat) -> CGFloat {
            guard isActive else { return CGFloat(index) * rowStride }
            var liftedBefore = 0
            for lifted in liftedIndices where lifted < index {
                liftedBefore += 1
            }
            let shiftsForGap =
                gapAnchorIndex.map { gapInsertsBeforeAnchor ? index >= $0 : index > $0 } ?? false
            let gapBefore: CGFloat = shiftsForGap ? gapHeight : 0
            return CGFloat(index - liftedBefore) * rowStride + gapBefore
        }

        /// Converts a projected visible row position (after lifted rows collapse)
        /// back to the corresponding item index so lifted rows above the viewport
        /// never starve visible destination rows below.
        func itemIndex(forProjectedRow projectedRow: Int, itemCount: Int) -> Int {
            guard isActive, !liftedIndices.isEmpty else { return projectedRow }
            if projectedRow <= 0 { return projectedRow }
            var index = projectedRow
            for lifted in liftedIndices {
                if lifted <= index {
                    index += 1
                } else {
                    break
                }
            }
            return min(index, max(0, itemCount - 1))
        }
    }

    private static let overscanRows = 2
    private static let defaultPoolCapacity = 24

    let items: [BrowserSidebarListItem]
    let itemsRevision: UUID
    let rowStride: CGFloat
    let context: BrowserSidebarListContext
    let visibleBand: BrowserSidebarVisibleBand

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction: BrowserSidebarInteractionState?
    @Environment(\.browserSidebarScrollRegionID) private var scrollRegionID
    @State private var runFrame: CGRect = .zero
    @State private var virtualRunID = UUID()
    @State private var poolCapacity = defaultPoolCapacity

    private var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: context.space)
    }

    var body: some View {
        let visibleRange = visibleBand.viewport.visibleRange ?? 0...900
        let reorderState = sidebarInteraction?.sidebarReorderState
        let isDragging = reorderState?.isDragging == true
        let projection = dragProjection(in: reorderState)
        let totalHeight = projection.totalHeight(itemCount: items.count, rowStride: rowStride)
        let viewportHeight = max(rowStride, visibleRange.upperBound - visibleRange.lowerBound)
        let neededPool = Int(ceil(viewportHeight / rowStride)) + Self.overscanRows * 2
        let effectivePool = isDragging ? poolCapacity : max(poolCapacity, neededPool)

        let localMinY = visibleRange.lowerBound - runFrame.minY
        let localMaxY = visibleRange.upperBound - runFrame.minY
        let overscanHeight = CGFloat(Self.overscanRows) * rowStride
        let isNearViewport = localMaxY >= -overscanHeight && localMinY <= totalHeight + overscanHeight

        let assignment = slotAssignments(
            poolSize: effectivePool,
            localMinY: localMinY,
            isNearViewport: isNearViewport,
            projection: projection
        )
        let _ = reorderState?.updateVirtualRunVisibleIndices(
            assignment.visibleRange,
            for: virtualRunID,
            in: spaceAssignment
        )

        ZStack(alignment: .top) {
            ForEach(0..<effectivePool, id: \.self) { slot in
                if let itemIndex = assignment.slots[slot] {
                    BrowserSidebarRecycledTabSlot(
                        item: items[itemIndex],
                        yOffset: projection.yOffset(for: itemIndex, rowStride: rowStride),
                        context: context
                    )
                    .equatable()
                }
            }
            if let overflowItemIndex = assignment.overflow {
                BrowserSidebarRecycledTabSlot(
                    item: items[overflowItemIndex],
                    yOffset: projection.yOffset(for: overflowItemIndex, rowStride: rowStride),
                    context: context
                )
                .equatable()
            }
        }
        .environment(\.browserSidebarUsesVirtualRowGeometry, true)
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight, alignment: .top)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: BrowserSidebarVisibleBand.contentSpace)
        } action: { frame in
            if abs(runFrame.minX - frame.minX) > 0.5 || abs(runFrame.minY - frame.minY) > 0.5
                || abs(runFrame.width - frame.width) > 0.5 || abs(runFrame.height - frame.height) > 0.5
            {
                runFrame = frame
                registerVirtualRun(frame: frame, visibleRange: assignment.visibleRange)
            }
        }
        .onChange(of: itemsRevision) { _, _ in
            registerVirtualRun(frame: runFrame, visibleRange: assignment.visibleRange)
        }
        .onChange(of: rowStride) { _, _ in
            registerVirtualRun(frame: runFrame, visibleRange: assignment.visibleRange)
        }
        .onChange(of: spaceAssignment) { oldSpace, _ in
            reorderState?.removeVirtualRun(for: virtualRunID, in: oldSpace)
            registerVirtualRun(frame: runFrame, visibleRange: assignment.visibleRange)
        }
        .onChange(of: effectivePool) { _, next in
            if next > poolCapacity {
                poolCapacity = next
            }
        }
        .onDisappear {
            reorderState?.removeVirtualRun(for: virtualRunID, in: spaceAssignment)
        }
    }

    private func registerVirtualRun(frame: CGRect, visibleRange: Range<Int>) {
        guard let reorderState = sidebarInteraction?.sidebarReorderState,
            !frame.isEmpty,
            let firstItem = items.first,
            case .tab(let firstTab) = firstItem.content
        else { return }
        let itemIDs = items.map(\.id)
        var indexByID: [BrowserSidebarReorderItemID: Int] = [:]
        indexByID.reserveCapacity(itemIDs.count)
        for (index, id) in itemIDs.enumerated() {
            indexByID[id] = index
        }
        let section = BrowserSidebarReorderSection.tabs(
            placement: firstTab.placement,
            folderID: firstTab.folderID
        )
        let capturedContext = context
        reorderState.register(
            virtualRun: BrowserSidebarReorderGeometry.VirtualRowRun(
                id: virtualRunID,
                space: spaceAssignment,
                section: section,
                scrollRegionID: scrollRegionID,
                frame: frame,
                rowStride: rowStride,
                itemIDs: itemIDs,
                itemIndexByID: indexByID,
                visibleIndices: visibleRange,
                auxiliaryClick: { tabID in
                    guard let tab = capturedContext.space.tabs.model(tabID) else { return }
                    let configuration = BrowserSidebarTabRowConfiguration(
                        tab: tab,
                        context: capturedContext,
                        isSelected: capturedContext.window.shownTabIDs.contains(tabID),
                        isLoaded: capturedContext.isLoaded(tabID),
                        isSplitGroupMember: false,
                        spacePresentation: nil
                    )
                    guard configuration.isCurrentAndUnlocked else { return }
                    BrowserTabMiddleClickAction(for: tab.placement).perform(on: configuration)
                }
            )
        )
    }

    private func slotAssignments(
        poolSize: Int,
        localMinY: CGFloat,
        isNearViewport: Bool,
        projection: DragProjection
    ) -> (slots: [Int?], overflow: Int?, visibleRange: Range<Int>) {
        var slots = [Int?](repeating: nil, count: poolSize)
        var overflow: Int?
        let liftOwnerIndex = projection.liftOwnerIndex
        let pinnedSlot = liftOwnerIndex.map { $0 % poolSize }
        if let liftOwnerIndex, let pinnedSlot {
            slots[pinnedSlot] = liftOwnerIndex
        }
        guard isNearViewport, !items.isEmpty else {
            return (slots, overflow, 0..<0)
        }
        let windowCount = min(items.count, poolSize)
        let projectedStart = Int(floor(localMinY / rowStride)) - Self.overscanRows
        let idealStart = projection.itemIndex(forProjectedRow: projectedStart, itemCount: items.count)
        let maxStart = max(0, items.count - windowCount)
        let windowStart = min(max(0, idealStart), maxStart)
        let windowEnd = windowStart + windowCount - 1
        for itemIndex in windowStart...windowEnd {
            if itemIndex == liftOwnerIndex { continue }
            let slot = itemIndex % poolSize
            if slot == pinnedSlot {
                overflow = itemIndex
            } else {
                slots[slot] = itemIndex
            }
        }
        return (slots, overflow, windowStart..<(windowEnd + 1))
    }

    private func dragProjection(in state: BrowserSidebarReorderState?) -> DragProjection {
        guard let state, state.layout.isActive else { return .idle }
        let liftOwnerID = state.lift?.item.id
        let gapAnchor = state.layout.gap?.anchor
        var liftedIndices: [Int] = []
        var liftOwnerIndex: Int?
        var gapAnchorIndex: Int?
        var gapInsertsBeforeAnchor = false
        for index in items.indices {
            let itemID = items[index].id
            if state.isLifted(itemID) {
                liftedIndices.append(index)
            }
            if itemID == liftOwnerID {
                liftOwnerIndex = index
            }
            if let gapAnchor {
                switch gapAnchor {
                case .before(let id):
                    if id == itemID {
                        gapAnchorIndex = index
                        gapInsertsBeforeAnchor = true
                    }
                case .after(let id):
                    if id == itemID {
                        gapAnchorIndex = index
                        gapInsertsBeforeAnchor = false
                    }
                case .emptySection:
                    break
                }
            }
        }
        return DragProjection(
            isActive: true,
            liftedIndices: liftedIndices,
            liftOwnerIndex: liftOwnerIndex,
            gapAnchorIndex: gapAnchorIndex,
            gapInsertsBeforeAnchor: gapInsertsBeforeAnchor,
            gapHeight: state.layout.gapHeight
        )
    }
}

private struct BrowserSidebarRecycledTabSlot: View, @MainActor Equatable {
    let item: BrowserSidebarListItem
    let yOffset: CGFloat
    let context: BrowserSidebarListContext

    static func == (lhs: BrowserSidebarRecycledTabSlot, rhs: BrowserSidebarRecycledTabSlot) -> Bool {
        lhs.item == rhs.item && lhs.yOffset == rhs.yOffset && lhs.context == rhs.context
    }

    var body: some View {
        if case .tab(let tab) = item.content {
            BrowserSidebarTabRow(tab: tab, context: context)
                .equatable()
                .modifier(BrowserSidebarFolderRowIndent(depth: item.depth))
                .environment(\.sidebarLayerDepth, item.depth)
                .offset(y: yOffset)
        }
    }
}
