import CoreGraphics
import Foundation

// MARK: - Types

/// A drop a target makes of a lift: the core's intent, the other Space it
/// moves the lift to, if any, which the window follows when the core moves it
/// there, and whether the lift leaves its Space.
struct BrowserSidebarDrop {
    let intent: any SidebarDrop
    var destination: SpaceModel? = nil
    /// Whether the lift leaves the Space it was lifted in, so a selection it
    /// carried is let go rather than kept selected where it landed.
    var leavesSpace = false
}

/// Where a lifted sidebar item will land when released.
struct BrowserSidebarReorderTarget: Equatable, Sendable {
    // MARK: - Types

    /// An insertion into an ordered section.
    struct Insertion: Equatable, Sendable {
        let section: BrowserSidebarReorderSection
        let beforeID: BrowserSidebarReorderItemID?
        let index: Int
    }

    /// An insertion into the split-view cards shown for a Space.
    struct SplitInsertion: Equatable, Sendable {
        let assignment: BrowserSpaceRuntimeAssignment
        let index: Int
    }

    /// Self-describing landing kind for a resolved drop target. Each kind
    /// carries its own verdict, drop-intent builder, preview shape and landing
    /// frame resolution rather than switching on a case tag.
    struct Kind: Equatable, Sendable {
        // MARK: - Types

        private enum Identity: Equatable, Sendable {
            case insert(Insertion)
            case intoFolder(UUID)
            case createCurrentFolder(UUID)
            case space(BrowserSpaceRuntimeAssignment)
            case splitInsert(SplitInsertion)
        }

        typealias LandingFrameResolver =
            @MainActor @Sendable (
                BrowserSidebarReorderLayout,
                () -> (layout: BrowserPinnedTabReorderLayout, frame: CGRect, emptyHeight: CGFloat)?,
                [BrowserSidebarReorderItemID: BrowserSidebarReorderGeometry.RegisteredRow]
            ) -> CGRect?

        // MARK: - Variables

        private let identity: Identity
        let insertion: Insertion?
        let splitInsertion: SplitInsertion?
        private let resolveVerdict:
            @MainActor @Sendable (BrowserSidebarLiftPlan, DropTargetList) -> BrowserSidebarDropVerdict
        private let resolveDrop: @MainActor @Sendable (TabSelection, SpaceModel, BrowserStore) -> BrowserSidebarDrop?
        private let resolvePreviewShape: @Sendable (BrowserTabDragPreviewShape?) -> BrowserTabDragPreviewShape?
        private let resolveLandingFrame: LandingFrameResolver

        // MARK: - Actions - Factories

        /// Insert into an ordered section before `beforeID` (`nil` appends).
        /// `index` is the resolved slot, used to displace neighbours.
        static func insert(
            section: BrowserSidebarReorderSection,
            beforeID: BrowserSidebarReorderItemID?,
            index: Int
        ) -> Self {
            let insertion = Insertion(section: section, beforeID: beforeID, index: index)
            return Self(
                identity: .insert(insertion),
                insertion: insertion,
                splitInsertion: nil,
                resolveVerdict: { plan, targets in
                    plan.verdict(onList: section.list(in: targets))
                },
                resolveDrop: { selection, space, browser in
                    let (placement, folderID) = section.list(in: space)
                    return BrowserSidebarDrop(
                        intent: DropIntoList(
                            workspaceID: browser.family.workspaceID, windowID: browser.windowID, spaceID: space.id,
                            selection: selection, section: placement, folderID: folderID,
                            beforeTabID: beforeID?.anchorTabID(in: space, lifted: Set(selection.memberTabIDs)),
                            beforeFolderID: beforeID?.folderID)
                    )
                },
                resolvePreviewShape: { _ in section.restingPreviewShape },
                resolveLandingFrame: { layout, pinned, _ in
                    if section.usesGridOrdering, let pinned = pinned() {
                        return pinned.layout.frame(for: .gap, in: pinned.frame)
                    }
                    return layout.gapFrame
                }
            )
        }

        /// Land inside a collapsed folder.
        static func intoFolder(_ folderID: UUID) -> Self {
            Self(
                identity: .intoFolder(folderID),
                insertion: nil,
                splitInsertion: nil,
                resolveVerdict: { plan, targets in
                    plan.verdict(onList: targets.lists.first { $0.folderID == folderID })
                },
                resolveDrop: { selection, space, browser in
                    guard let folder = space.folders.model(folderID) else { return nil }
                    return BrowserSidebarDrop(
                        intent: DropIntoList(
                            workspaceID: browser.family.workspaceID, windowID: browser.windowID, spaceID: space.id,
                            selection: selection, section: folder.location, folderID: folderID,
                            beforeTabID: nil, beforeFolderID: nil)
                    )
                },
                resolvePreviewShape: { _ in .row },
                resolveLandingFrame: { layout, _, rows in
                    rows[.folder(folderID)].flatMap { layout.frame(for: $0.row) }
                }
            )
        }

        /// Create a folder around an open tab.
        static func createCurrentFolder(_ tabID: UUID) -> Self {
            Self(
                identity: .createCurrentFolder(tabID),
                insertion: nil,
                splitInsertion: nil,
                resolveVerdict: { _, targets in
                    targets.folderAroundTabIDs.contains(tabID) ? .allowed : .unavailable
                },
                resolveDrop: { selection, space, browser in
                    BrowserSidebarDrop(
                        intent: DropAroundTab(
                            workspaceID: browser.family.workspaceID, windowID: browser.windowID, spaceID: space.id,
                            selection: selection, tabID: tabID, title: BrowserStore.newFolderTitle)
                    )
                },
                resolvePreviewShape: { _ in .row },
                resolveLandingFrame: { layout, _, rows in
                    rows[.tab(tabID)].flatMap { layout.frame(for: $0.row) }
                }
            )
        }

        /// Move to another space.
        static func space(_ assignment: BrowserSpaceRuntimeAssignment) -> Self {
            Self(
                identity: .space(assignment),
                insertion: nil,
                splitInsertion: nil,
                resolveVerdict: { plan, targets in
                    guard targets.spaceIDs.contains(assignment.spaceID) else { return .unavailable }
                    return plan.verdict(onSpace: assignment.spaceID)
                },
                resolveDrop: { selection, space, browser in
                    guard let destinationSpace = browser.spaceModel(assignment.spaceID),
                        destinationSpace.profileID == assignment.profileID
                    else { return nil }
                    return BrowserSidebarDrop(
                        intent: DropOnSpace(
                            workspaceID: browser.family.workspaceID, windowID: browser.windowID, spaceID: space.id,
                            selection: selection, destinationSpaceID: assignment.spaceID),
                        destination: destinationSpace,
                        leavesSpace: true
                    )
                },
                resolvePreviewShape: { resting in resting },
                resolveLandingFrame: { _, _, _ in nil }
            )
        }

        /// Join the cards the content area is presenting, as the card at
        /// `index` among them. The index counts presented cards only — the drop
        /// placeholder is not one of them — so it stays put as the row of cards
        /// shifts to make room.
        static func splitInsert(assignment: BrowserSpaceRuntimeAssignment, index: Int) -> Self {
            let split = SplitInsertion(assignment: assignment, index: index)
            return Self(
                identity: .splitInsert(split),
                insertion: nil,
                splitInsertion: split,
                resolveVerdict: { _, targets in
                    BrowserSidebarDropVerdict(targets.split.map { $0.refusal })
                },
                resolveDrop: { selection, space, browser in
                    // The cards on show are the shown tab's split, so the shown tab is
                    // the one the lift joins, and a window showing one tab makes a split.
                    guard assignment.spaceID == space.id, let shown = browser.selectedTabID(in: space.id) else {
                        return nil
                    }
                    return BrowserSidebarDrop(
                        intent: DropIntoSplit(
                            workspaceID: browser.family.workspaceID, windowID: browser.windowID, spaceID: space.id,
                            selection: selection, targetTabID: shown, index: index)
                    )
                },
                resolvePreviewShape: { _ in .webpageCard },
                resolveLandingFrame: { _, _, _ in nil }
            )
        }

        // MARK: - Actions - Verdicts

        /// What the core says of dropping `plan`'s lift here, from the drop
        /// `targets` it listed as the lift began: whether it may land, the
        /// rule that refuses it, or that the core offers no such target.
        @MainActor
        func verdict(in plan: BrowserSidebarLiftPlan, targets: DropTargetList) -> BrowserSidebarDropVerdict {
            resolveVerdict(plan, targets)
        }

        // MARK: - Actions - Dropping

        /// The drop that lands `selection`, lifted in `space` of `browser`'s
        /// window, here: the core's intent, the Space the window follows the
        /// lift to, if any, and whether it leaves its Space; nil where the
        /// target no longer stands.
        @MainActor
        func drop(
            lifting selection: TabSelection, in space: SpaceModel, from browser: BrowserStore
        ) -> BrowserSidebarDrop? {
            resolveDrop(selection, space, browser)
        }

        // MARK: - Actions - Presentation

        /// The shape a lifted tab takes over this target, or `resting`, the
        /// shape it keeps where the target says nothing of its own.
        func previewShape(resting: BrowserTabDragPreviewShape?) -> BrowserTabDragPreviewShape? {
            resolvePreviewShape(resting)
        }

        /// Where a lift released here settles in the sidebar, from the lift's
        /// `layout`, the `pinned` grid's and the registered `rows`; nil where it
        /// leaves the sidebar.
        @MainActor
        func landingFrame(
            layout: BrowserSidebarReorderLayout,
            pinned: @autoclosure () -> (layout: BrowserPinnedTabReorderLayout, frame: CGRect, emptyHeight: CGFloat)?,
            rows: [BrowserSidebarReorderItemID: BrowserSidebarReorderGeometry.RegisteredRow]
        ) -> CGRect? {
            resolveLandingFrame(layout, pinned, rows)
        }

        // MARK: - Actions - Equality

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.identity == rhs.identity
        }
    }

    // MARK: - Variables

    let kind: Kind

    var section: BrowserSidebarReorderSection? {
        kind.insertion?.section
    }
}
