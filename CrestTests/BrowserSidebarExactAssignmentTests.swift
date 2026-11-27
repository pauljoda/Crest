import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarExactAssignmentTests: XCTestCase {
    func testCapturedTabCloseRejectsAReplacementBrowsingProfile() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        replaceProfile(of: context.source, in: context.store)

        XCTAssertFalse(
            context.store.closeTab(
                context.sourceTab.id,
                matching: assignment
            )
        )
        XCTAssertTrue(
            try XCTUnwrap(context.store.spaceModel(context.source.id))
                .tabs.contains(context.sourceTab.id)
        )
    }

    func testVirtualRowRunReorderPreservesScrollOriginLiftPreviewAndGapMovement() throws {
        let state = BrowserSidebarReorderState()
        let space = BrowserSpaceRuntimeAssignment(spaceID: fixedUUID(10), profileID: fixedUUID(11))
        let regionID = UUID()
        let runID = UUID()
        let section = BrowserSidebarReorderSection.tabs(placement: .current, folderID: nil)
        let tabIDs = (0..<60).map { _ in UUID() }
        let itemIDs = tabIDs.map(BrowserSidebarReorderItemID.tab)
        let indexByID = Dictionary(uniqueKeysWithValues: itemIDs.enumerated().map { ($1, $0) })
        let rowStride: CGFloat = 36

        // Register viewport and scrolled content origin (scrolled down 1080pt = 30 rows).
        let viewport = CGRect(x: 0, y: 100, width: 240, height: 600)
        state.register(scrollRegionFrame: viewport, for: regionID)
        state.register(scrollContentOrigin: CGPoint(x: 0, y: viewport.minY - 1080), for: regionID)
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(section),
                frame: CGRect(x: 0, y: 0, width: 240, height: CGFloat(tabIDs.count) * rowStride),
                minimumHeight: 36,
                supportsTouch: false
            ),
            for: UUID(),
            scrollRegionID: regionID,
            isContentRelative: true
        )
        let run = BrowserSidebarReorderGeometry.VirtualRowRun(
            id: runID,
            space: space,
            section: section,
            scrollRegionID: regionID,
            frame: CGRect(x: 0, y: 0, width: 240, height: CGFloat(tabIDs.count) * rowStride),
            rowStride: rowStride,
            itemIDs: itemIDs,
            itemIndexByID: indexByID,
            visibleIndices: 28..<50
        )
        state.register(virtualRun: run)

        // Row 35 sits at content y = 1260, so global y = 100 - 1080 + 1260 = 280.
        let pickedFrame = try XCTUnwrap(state.frame(ofRow: .tab(tabIDs[35]), in: space))
        XCTAssertEqual(pickedFrame.minY, 280, accuracy: 0.5)
        XCTAssertEqual(state.auxiliaryClickTabID(at: CGPoint(x: 120, y: pickedFrame.midY), in: space), tabIDs[35])

        let pickedItem = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(tabID: tabIDs[35], spaceID: space.spaceID, profileID: space.profileID)
        )
        let startPointer = CGPoint(x: 120, y: pickedFrame.midY)
        state.begin(item: pickedItem, section: section, at: startPointer)

        // Floating lift preview must stay right under the pointer (not shifted by scroll).
        let preview = try XCTUnwrap(state.liftPreview)
        XCTAssertEqual(preview.grabOffset.height, rowStride / 2, accuracy: 1.0)
        XCTAssertEqual(preview.rowWidth, 240, accuracy: 0.5)

        // Updating the virtual run frame mid-drag (e.g. projected height change) must be held, not corrupt geometry.
        var shrunkenRun = run
        shrunkenRun.frame = CGRect(x: 0, y: 0, width: 240, height: CGFloat(tabIDs.count - 1) * rowStride)
        state.register(virtualRun: shrunkenRun)
        XCTAssertEqual(try XCTUnwrap(state.frame(ofRow: .tab(tabIDs[35]), in: space)).minY, 280, accuracy: 0.5)

        // Moving the pointer to the top edge of row 33 opens the gap before row 33.
        state.update(pointer: CGPoint(x: 120, y: pickedFrame.minY - rowStride * 2 + 4))
        XCTAssertEqual(state.layout.gap?.anchor, .before(.tab(tabIDs[33])))

        // Resting on row 33's projected center (shifted down by the open gap) offers nesting.
        state.update(pointer: CGPoint(x: 120, y: pickedFrame.midY - rowStride))
        XCTAssertEqual(state.resolvedTarget?.kind, .createCurrentFolder(tabIDs[33]))

        // Moving the pointer down to the top edge of row 37 moves the gap cleanly.
        state.update(pointer: CGPoint(x: 120, y: pickedFrame.minY + rowStride * 2 + 4))
        XCTAssertNotEqual(state.layout.gap?.anchor, .before(.tab(tabIDs[33])))
        XCTAssertNotNil(state.layout.gap)

        state.cancel()
    }

    func testFolderTabAuxiliaryClickSurvivesMoveCollapseAndOwnerOverlap() throws {
        let folderID = UUID()
        let subFolderID = UUID()
        let collapsedFolderID = UUID()
        let folderTabID = UUID()
        let collapsedFolderTabID = UUID()
        let unfiledSavedTabID = UUID()
        let currentTabID = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let folder = FolderState.Seed(id: folderID, title: "Work", location: .saved, isCollapsed: false)
        let subFolder = FolderState.Seed(
            id: subFolderID, title: "Sub", location: .saved, parentID: folderID, isCollapsed: false)
        let collapsedFolder = FolderState.Seed(
            id: collapsedFolderID, title: "Collapsed", location: .saved, isCollapsed: true)
        let folderTab = TabState.Seed(
            id: folderTabID, title: "Folder Tab", url: url, placement: .saved, folderID: folderID)
        let collapsedFolderTab = TabState.Seed(
            id: collapsedFolderTabID, title: "Collapsed Folder Tab", url: url, placement: .saved,
            folderID: collapsedFolderID)
        let unfiledSavedTab = TabState.Seed(id: unfiledSavedTabID, title: "Unfiled Saved", url: url, placement: .saved)
        let currentTab = TabState.Seed(id: currentTabID, title: "Current Tab", url: url, placement: .current)
        var space = SpaceState.Seed.blank(number: 1)
        space.folders = [folder, subFolder, collapsedFolder]
        space.tabs = [folderTab, collapsedFolderTab, unfiledSavedTab, currentTab]

        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]),
            showing: space.id,
            tabs: [space.id: currentTabID]
        )
        let pages = BrowserPagePool(browser: browser)
        let spaceAccess = BrowserSpaceAccessController()
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let liveSpace = try XCTUnwrap(browser.shownSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: liveSpace)
        let capabilities = BrowserInteractionCapabilities()

        var unloadedTabIDs: [UUID] = []
        let pageAccess = BrowserSidebarPageAccess(
            containsResidentPage: { id in
                id == folderTabID || id == collapsedFolderTabID || id == unfiledSavedTabID || id == currentTabID
            },
            containsResidentPageMatching: {
                $0.tabID == folderTabID || $0.tabID == collapsedFolderTabID || $0.tabID == unfiledSavedTabID
                    || $0.tabID == currentTabID
            },
            siteThemeIconAccent: { _ in nil },
            residencyRevision: { 1 },
            selectPages: {},
            deactivatePagePresentation: {},
            unloadPages: { ids, _ in unloadedTabIDs.append(contentsOf: ids) },
            pullFavicon: { _, _ in nil },
            downloadCenter: BrowserDownloadCenter()
        )
        let tabActions = BrowserSidebarTabActions(
            assignment: assignment,
            browser: browser,
            reorderState: interaction.sidebarReorderState,
            pages: pages,
            spaceAccess: spaceAccess
        )
        let windowModel = try XCTUnwrap(browser.windowModel)
        let listContext = BrowserSidebarListContext(
            space: liveSpace,
            window: windowModel,
            favicons: browser.core.state.favicons,
            browser: browser,
            spaceAccess: spaceAccess,
            pageAccess: pageAccess,
            tabActions: tabActions,
            capabilities: capabilities,
            select: { _ in }
        )

        let rootView = VStack(spacing: 0) {
            Color.clear.frame(height: 100)
            SpaceSidebarTabListScroll(browser: browser, space: liveSpace) {
                Color.clear
            } content: {
                BrowserSidebarTabList(
                    context: listContext,
                    alwaysShowsSavedTabs: true,
                    showsClearAction: false,
                    openNewTab: {}
                )
            }
        }
        .environment(interaction)
        .environment(\.sidebarSpacePresentation, SidebarSpacePresentation(space: liveSpace, isUnlocked: true))
        .environment(\.sidebarSpaceIsSelected, true)
        .frame(width: 260, height: 600)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 260, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 600)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        func pump(_ ticks: Int = 10) {
            for _ in 0..<ticks { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04)) }
        }
        pump()

        let state = interaction.sidebarReorderState

        // Moving an unfiled saved tab into a folder must keep auxiliary-click hit-testing intact.
        browser.moveTab(unfiledSavedTabID, to: .saved, folderID: folderID, before: nil)
        pump(12)
        let movedFrame = try XCTUnwrap(state.frame(ofRow: .tab(unfiledSavedTabID), in: assignment))
        let movedMid = CGPoint(x: movedFrame.midX, y: movedFrame.midY)
        XCTAssertEqual(state.auxiliaryClickTabID(at: movedMid, in: assignment), unfiledSavedTabID)
        XCTAssertEqual(state.selectionItem(at: movedMid, in: assignment), .tab(unfiledSavedTabID))

        // Running the middle-click action unloads the moved saved tab inside the folder.
        let movedTab = try XCTUnwrap(liveSpace.tabs.model(unfiledSavedTabID))
        let movedConfig = BrowserSidebarTabRowConfiguration(
            tab: movedTab, context: listContext, isSelected: false, isLoaded: true, isSplitGroupMember: false)
        BrowserTabMiddleClickAction(for: movedTab.placement).perform(on: movedConfig)
        XCTAssertEqual(unloadedTabIDs, [unfiledSavedTabID])

        // Expanding a collapsed folder resolves its tabs for auxiliary clicks.
        browser.setFolderCollapsed(collapsedFolderID, in: liveSpace.id, isCollapsed: false)
        pump(12)
        let expandedFrame = try XCTUnwrap(state.frame(ofRow: .tab(collapsedFolderTabID), in: assignment))
        XCTAssertEqual(
            state.auxiliaryClickTabID(at: CGPoint(x: expandedFrame.midX, y: expandedFrame.midY), in: assignment),
            collapsedFolderTabID)

        // Collapsing a folder with a subfolder keeps its loaded tab hit-testable.
        browser.setFolderCollapsed(folderID, in: liveSpace.id, isCollapsed: true)
        pump(12)
        let keptFrame = try XCTUnwrap(state.frame(ofRow: .tab(folderTabID), in: assignment))
        XCTAssertEqual(
            state.auxiliaryClickTabID(at: CGPoint(x: keptFrame.midX, y: keptFrame.midY), in: assignment),
            folderTabID)

        // Departing owner clearing selection-disabled must not unmask a surviving owner.
        let ownerA = UUID()
        let ownerB = UUID()
        state.setRowSelectionDisabled(true, for: .tab(folderTabID), in: assignment, owner: ownerA)
        state.setRowSelectionDisabled(true, for: .tab(folderTabID), in: assignment, owner: ownerB)
        state.setRowSelectionDisabled(false, for: .tab(folderTabID), in: assignment, owner: ownerA)
        XCTAssertNil(state.selectionItem(at: CGPoint(x: keptFrame.midX, y: keptFrame.midY), in: assignment))
        state.setRowSelectionDisabled(false, for: .tab(folderTabID), in: assignment, owner: ownerB)
        XCTAssertEqual(
            state.selectionItem(at: CGPoint(x: keptFrame.midX, y: keptFrame.midY), in: assignment),
            .tab(folderTabID))

        // Non-content-relative rows (e.g. pinned tiles or folder preview cards) must not double-match.
        let externalTabID = UUID()
        let externalOwner = UUID()
        let externalFrame = CGRect(x: 300, y: 120, width: 220, height: 36)
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(externalTabID), space: assignment,
                section: .tabs(placement: .saved, folderID: collapsedFolderID), frame: externalFrame),
            owner: externalOwner,
            scrollRegionID: nil,
            isContentRelative: false
        )
        XCTAssertNil(
            state.auxiliaryClickTabID(at: CGPoint(x: externalFrame.midX, y: externalFrame.midY), in: assignment))
        state.removeRow(.tab(externalTabID), owner: externalOwner)
    }

    private func makeContext(sourceIsProtected: Bool = false) -> (
        store: BrowserStore,
        source: SpaceState.Seed,
        destination: SpaceState.Seed,
        sourceTab: TabState.Seed
    ) {
        let sourceTab = TabState.Seed(
            id: fixedUUID(1),
            title: "Source tab",
            url: nil,
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let destinationTab = TabState.Seed.startPage(
            id: fixedUUID(2),
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let source = SpaceState.Seed(
            id: fixedUUID(3),
            profileID: fixedUUID(4),
            name: "Source",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab],
            accessPolicy: sourceIsProtected
                ? .deviceOwnerAuthentication
                : .open
        )
        let destination = SpaceState.Seed(
            id: fixedUUID(5),
            profileID: fixedUUID(6),
            name: "Destination",
            symbol: "2.circle",
            accent: .rose,
            folders: [],
            tabs: [destinationTab]
        )
        let store = BrowserStore(seed: SessionState.Seed(spaces: [source, destination]), core: .hostingPages())
        return (store, source, destination, sourceTab)
    }

    private func replaceProfile(
        of space: SpaceState.Seed,
        in store: BrowserStore
    ) {
        store.replaceProfileForTesting(of: space.id, with: fixedUUID(7))
    }

    private func fixedUUID(_ suffix: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x2D,
                0x45, 0x58, 0x41, 0x43, 0x54, 0x00, 0x00, suffix
            )
        )
    }

}
