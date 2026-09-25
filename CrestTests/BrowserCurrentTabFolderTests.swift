import XCTest

@testable import Crest

@MainActor
final class BrowserCurrentTabFolderTests: XCTestCase {
    func testTabDropBetweenSiblingFoldersCommitsAndRestoresAtTheParentLevel() throws {
        for location in [BrowserFolderLocation.saved, .current] {
            for nested in [false, true] {
                for sourcePlacement in [TabPlacement.pinned, .saved, .current] {
                    var space = BrowserSession.makeBlankSpace(number: 1)
                    let parent = nested ? BrowserFolder(title: "Parent", location: location) : nil
                    let first = BrowserFolder(title: "First", location: location, parentID: parent?.id)
                    let second = BrowserFolder(title: "Second", location: location, parentID: parent?.id)
                    space.folders = [parent, first, second].compactMap { $0 }
                    let firstTab = BrowserTab(
                        title: "First", url: URL(string: "https://example.com/first"),
                        placement: location.tabPlacement, folderID: first.id)
                    let secondTab = BrowserTab(
                        title: "Second", url: URL(string: "https://example.com/second"),
                        placement: location.tabPlacement, folderID: second.id)
                    let moving = BrowserTab(
                        title: "Between", url: URL(string: "https://example.com/between"), placement: sourcePlacement)
                    space.tabs = [firstTab, secondTab, moving]
                    let browser = makeStore(space, showing: firstTab.id)
                    let target = BrowserSidebarReorderTarget(
                        kind: .insert(
                            section: .tabs(placement: location.tabPlacement, folderID: parent?.id),
                            beforeID: .folder(second.id), index: 1))
                    XCTAssertTrue(
                        BrowserSidebarReorderCommit(browser: browser, spaceAccess: BrowserSpaceAccessController())
                            .apply(
                                target,
                                for: .tab(.init(tabID: moving.id, spaceID: space.id, profileID: space.profile.id))))
                    let restored = try JSONDecoder().decode(
                        BrowserSession.self, from: JSONEncoder().encode(browser.session))
                    let result = try XCTUnwrap(restored.space(id: space.id))
                    XCTAssertEqual(result.tabs.first { $0.id == moving.id }?.folderID, parent?.id)
                    XCTAssertEqual(browser.selectedTabID(in: space.id), firstTab.id)
                    XCTAssertEqual(
                        BrowserSidebarFolderListItem.items(
                            tabs: result.tabs, tree: result.folderTree,
                            location: location, parentID: parent?.id
                        ).map(\.id), [.folder(first.id), .tab(moving.id), .folder(second.id)])
                }
            }
        }
    }

    func testTabDropBetweenEmptySiblingFoldersCommitsAndRestoresAtTheParentLevel() throws {
        for location in [BrowserFolderLocation.saved, .current] {
            for nested in [false, true] {
                for sourcePlacement in [TabPlacement.pinned, .saved, .current] {
                    var space = BrowserSession.makeBlankSpace(number: 1)
                    let parent = nested ? BrowserFolder(title: "Parent", location: location) : nil
                    let first = BrowserFolder(title: "First", location: location, parentID: parent?.id)
                    let second = BrowserFolder(title: "Second", location: location, parentID: parent?.id)
                    space.folders = [parent, first, second].compactMap { $0 }
                    let moving = BrowserTab(
                        title: "Between", url: URL(string: "https://example.com/between"), placement: sourcePlacement)
                    space.tabs = [moving]
                    let browser = makeStore(space, showing: moving.id)
                    let target = BrowserSidebarReorderTarget(
                        kind: .insert(
                            section: .tabs(placement: location.tabPlacement, folderID: parent?.id),
                            beforeID: .folder(second.id), index: 1))
                    XCTAssertTrue(
                        BrowserSidebarReorderCommit(browser: browser, spaceAccess: BrowserSpaceAccessController())
                            .apply(
                                target,
                                for: .tab(.init(tabID: moving.id, spaceID: space.id, profileID: space.profile.id))))
                    let restored = try JSONDecoder().decode(
                        BrowserSession.self, from: JSONEncoder().encode(browser.session))
                    let result = try XCTUnwrap(restored.space(id: space.id))
                    XCTAssertEqual(result.tabs.first { $0.id == moving.id }?.folderID, parent?.id)
                    XCTAssertEqual(browser.selectedTabID(in: space.id), moving.id)
                    XCTAssertEqual(
                        BrowserSidebarFolderListItem.items(
                            tabs: result.tabs, tree: result.folderTree,
                            location: location, parentID: parent?.id
                        ).map(\.id), [.folder(first.id), .tab(moving.id), .folder(second.id)])
                    let records = try BrowserCoreSync.project(browser.session, preferences: .default, records: [])
                        .map { BrowserSyncRecord.save($0, version: .init(logicalClock: 1, deviceID: UUID())) }
                    let synced = try BrowserCoreSync.materialize(
                        .freshInstallSeed, preferences: .default, records: records)
                    let syncedSpace = try XCTUnwrap(synced.space(id: space.id))
                    XCTAssertEqual(
                        BrowserSidebarFolderListItem.items(
                            tabs: syncedSpace.tabs, tree: syncedSpace.folderTree,
                            location: location, parentID: parent?.id
                        ).map(\.id), [.folder(first.id), .tab(moving.id), .folder(second.id)])
                    let commit = BrowserSidebarReorderCommit(
                        browser: browser, spaceAccess: BrowserSpaceAccessController())
                    let drag = BrowserSidebarReorderItem.tab(
                        .init(tabID: moving.id, spaceID: space.id, profileID: space.profile.id))
                    XCTAssertTrue(
                        commit.apply(
                            .init(
                                kind: .insert(
                                    section: .tabs(placement: location.tabPlacement, folderID: parent?.id),
                                    beforeID: .folder(first.id), index: 0)), for: drag))
                    var reordered = try XCTUnwrap(browser.selectedSpace)
                    XCTAssertEqual(
                        BrowserSidebarFolderListItem.items(
                            tabs: reordered.tabs, tree: reordered.folderTree, location: location, parentID: parent?.id
                        ).map(\.id), [.tab(moving.id), .folder(first.id), .folder(second.id)])
                    XCTAssertTrue(
                        commit.apply(
                            .init(
                                kind: .insert(
                                    section: .tabs(placement: location.tabPlacement, folderID: parent?.id),
                                    beforeID: nil, index: 2)), for: drag))
                    reordered = try XCTUnwrap(browser.selectedSpace)
                    XCTAssertEqual(
                        BrowserSidebarFolderListItem.items(
                            tabs: reordered.tabs, tree: reordered.folderTree, location: location, parentID: parent?.id
                        ).map(\.id), [.folder(first.id), .folder(second.id), .tab(moving.id)])
                }
            }
        }
    }

    func testEmptyFolderCanMoveBeforeATabAndAnotherEmptyFolder() throws {
        for location in [BrowserFolderLocation.saved, .current] {
            var space = BrowserSession.makeBlankSpace(number: 1)
            let first = BrowserFolder(title: "First", location: location)
            let second = BrowserFolder(title: "Second", location: location)
            let tab = BrowserTab(
                title: "Tab", url: URL(string: "https://example.com"), placement: location.tabPlacement)
            space.folders = [first, second]
            space.tabs = [tab]
            let browser = makeStore(space, showing: tab.id)
            let commit = BrowserSidebarReorderCommit(browser: browser, spaceAccess: BrowserSpaceAccessController())
            for (folder, before) in [(first, BrowserSidebarReorderItemID.tab(tab.id)), (second, .folder(first.id))] {
                XCTAssertTrue(
                    commit.apply(
                        .init(
                            kind: .insert(
                                section: .tabs(placement: location.tabPlacement, folderID: nil), beforeID: before,
                                index: 0)),
                        for: .folder(
                            .init(folderID: folder.id, spaceID: space.id, profileID: space.profile.id, memberTabIDs: [])
                        )))
            }
            let result = try XCTUnwrap(browser.selectedSpace)
            XCTAssertEqual(
                BrowserSidebarFolderListItem.items(tabs: result.tabs, tree: result.folderTree, location: location)
                    .map(\.id), [.folder(second.id), .folder(first.id), .tab(tab.id)])
        }
    }

    func testEmptyFolderBoundarySurvivesAnchorAndLastMemberRemoval() throws {
        for initiallyEmpty in [false, true] {
            for operation in ["delete", "close", "popupClose", "move", "pin"] {
                var space = BrowserSession.makeBlankSpace(number: 1)
                var folder = BrowserFolder(title: "Empty", location: .current)
                let moving = BrowserTab(
                    title: "Moving", url: URL(string: "https://example.com/moving"),
                    placement: .current, folderID: initiallyEmpty ? nil : folder.id)
                let after = BrowserTab(
                    title: "After", url: URL(string: "https://example.com/after"), placement: .current)
                if initiallyEmpty { folder.orderAnchorTabID = moving.id }
                space.folders = [folder]
                space.tabs = [moving, after]
                let browser = makeStore(space, showing: after.id)
                switch operation {
                case "delete":
                    XCTAssertTrue(browser.deleteTab(moving.id, matching: BrowserSpaceRuntimeAssignment(space: space)))
                case "close": XCTAssertTrue(browser.closeTab(moving.id))
                case "popupClose": XCTAssertTrue(browser.closeTab(moving.id, in: space.id))
                case "move": XCTAssertTrue(browser.moveTab(moving.id, to: .current))
                default: XCTAssertTrue(browser.moveTab(moving.id, to: .pinned))
                }
                let result = try XCTUnwrap(browser.session.space(id: space.id))
                XCTAssertEqual(
                    BrowserSidebarFolderListItem.items(
                        tabs: result.tabs, tree: result.folderTree, location: .current
                    ).first?.id, .folder(folder.id), operation)
            }
        }
    }

    func testPortableArchiveRebasesEmptyFolderBoundaryToImportedTabIDs() throws {
        var space = BrowserSession.makeBlankSpace(number: 1)
        let tab = BrowserTab(title: "After", url: URL(string: "https://example.com"), placement: .current)
        let folder = BrowserFolder(title: "Before", location: .current, orderAnchorTabID: tab.id)
        space.tabs = [tab]
        space.folders = [folder]
        let portable = try JSONDecoder().decode(PortableSpace.self, from: JSONEncoder().encode(PortableSpace(space)))
        let result = try portable.materialize()
        let importedTab = try XCTUnwrap(result.tabs.first)
        let importedFolder = try XCTUnwrap(result.folders.first)
        XCTAssertNotEqual(importedTab.id, tab.id)
        XCTAssertEqual(
            BrowserSidebarFolderListItem.items(
                tabs: result.tabs, tree: result.folderTree, location: .current
            ).map(\.id), [.folder(importedFolder.id), .tab(importedTab.id)])
    }

    func testSplitGroupDropsBetweenEmptyFoldersAsOneBlock() throws {
        for location in [BrowserFolderLocation.saved, .current] {
            var space = BrowserSession.makeBlankSpace(number: 1)
            let first = BrowserFolder(title: "First", location: location)
            let second = BrowserFolder(title: "Second", location: location)
            let groupID = SplitGroupID()
            let members = (0..<2).map {
                BrowserTab(
                    title: "Page \($0)", url: URL(string: "https://example.com/\($0)"),
                    placement: location.tabPlacement, splitGroupID: groupID)
            }
            space.folders = [first, second]
            space.tabs = members
            let browser = makeStore(space, showing: members[0].id)
            XCTAssertTrue(
                BrowserSidebarReorderCommit(browser: browser, spaceAccess: BrowserSpaceAccessController()).apply(
                    .init(
                        kind: .insert(
                            section: .tabs(placement: location.tabPlacement, folderID: nil),
                            beforeID: .folder(second.id), index: 1)),
                    for: .splitGroup(
                        .init(
                            groupID: groupID, spaceID: space.id, profileID: space.profile.id,
                            memberTabIDs: members.map(\.id)))))
            let result = try XCTUnwrap(browser.selectedSpace)
            XCTAssertEqual(
                BrowserSidebarFolderListItem.items(tabs: result.tabs, tree: result.folderTree, location: location)
                    .map(\.id), [.folder(first.id), .splitGroup(groupID), .folder(second.id)])
        }
    }

    func testEmptyFolderKeepsItsBoundaryBeforeAPopulatedSiblingRegardlessOfStorageOrder() throws {
        var space = BrowserSession.makeBlankSpace(number: 1)
        let populated = BrowserFolder(title: "Populated", location: .current)
        let member = BrowserTab(
            title: "Member", url: URL(string: "https://example.com/member"), placement: .current, folderID: populated.id
        )
        let empty = BrowserFolder(title: "Empty", location: .current, orderAnchorTabID: member.id)
        let moving = BrowserTab(title: "Moving", url: URL(string: "https://example.com/moving"), placement: .current)
        space.folders = [populated, empty]
        space.tabs = [member, moving]
        let browser = makeStore(space, showing: moving.id)
        XCTAssertTrue(
            browser.fileTabs(
                [moving.id], matching: BrowserSpaceRuntimeAssignment(space: space), into: nil, location: .current,
                beforeFolderID: populated.id))
        let result = try XCTUnwrap(browser.session.space(id: space.id))
        XCTAssertEqual(
            BrowserSidebarFolderListItem.items(tabs: result.tabs, tree: result.folderTree, location: .current)
                .map(\.id), [.folder(empty.id), .tab(moving.id), .folder(populated.id)])
    }

    func testDropBetweenEmptySavedFoldersKeepsSavedTabsBeforeCurrentTabs() throws {
        var space = BrowserSession.makeBlankSpace(number: 1)
        let first = BrowserFolder(title: "First")
        let second = BrowserFolder(title: "Second")
        let moving = BrowserTab(title: "Moving", url: URL(string: "https://example.com/moving"), placement: .current)
        let current = BrowserTab(title: "Current", url: URL(string: "https://example.com/current"), placement: .current)
        space.folders = [first, second]
        space.tabs = [moving, current]
        let browser = makeStore(space, showing: current.id)
        XCTAssertTrue(
            browser.fileTabs(
                [moving.id], matching: BrowserSpaceRuntimeAssignment(space: space), into: nil, location: .saved,
                beforeFolderID: second.id))
        XCTAssertEqual(browser.session.space(id: space.id)?.tabs.map(\.id), [moving.id, current.id])
    }

    func testSavedSubtreeMovesBothDirectionsAndRestoresWithoutLosingIdentityOrSplitMembership() throws {
        let rootFolder = BrowserFolder(title: "🧪 Research")
        let childFolder = BrowserFolder(title: "Child", parentID: rootFolder.id)
        let (root, child) = (rootFolder.id, childFolder.id)
        let split = SplitGroupID()
        let browser = makeBrowser { space in
            space.folders = [rootFolder, childFolder]
            for i in 0..<2 {
                space.tabs[i].placement = .saved
                space.tabs[i].folderID = child
                space.tabs[i].splitGroupID = split
            }
        }
        let space = try XCTUnwrap(browser.selectedSpace)
        let ids = Array(space.tabs.prefix(2).map(\.id))
        XCTAssertTrue(browser.setFolderCollapsed(child, in: space.id, isCollapsed: true))
        let original = browser.selectedSpace?.folders
        let item = BrowserSidebarReorderItem.folder(
            .init(folderID: root, spaceID: space.id, profileID: space.profile.id))
        let commit = BrowserSidebarReorderCommit(browser: browser, spaceAccess: BrowserSpaceAccessController())
        XCTAssertTrue(
            commit.apply(
                .init(kind: .insert(section: .tabs(placement: .current, folderID: nil), beforeID: nil, index: 0)),
                for: item))
        XCTAssertTrue(browser.selectedSpace?.folders.allSatisfy { $0.location == .current } == true)
        XCTAssertEqual(browser.selectedSpace?.folders.first { $0.id == child }?.parentID, root)
        XCTAssertEqual(browser.selectedSpace?.tabs.filter { $0.folderID == child }.map(\.id), ids)
        XCTAssertEqual(browser.selectedSpace?.splitGroupMembers(of: split).map(\.id), ids)
        var restored = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(browser.session))
        restored = try restored.openedAsSeed()
        XCTAssertEqual(restored.spaces[0].folders, browser.selectedSpace?.folders)
        XCTAssertEqual(restored.spaces[0].tabs.filter { $0.folderID == child }.map(\.id), ids)
        XCTAssertTrue(
            commit.apply(.init(kind: .insert(section: .folders(parentID: nil), beforeID: nil, index: 0)), for: item))
        XCTAssertEqual(browser.selectedSpace?.folders, original)
        XCTAssertTrue(
            browser.selectedSpace?.tabs.filter { ids.contains($0.id) }.allSatisfy {
                $0.placement == .saved && $0.folderID == child && $0.splitGroupID == split && $0.savedURL == $0.url
            } == true)
    }

    func testJoiningFolderRetainsDestinationPositionAndMovesWholeSplit() throws {
        let split = SplitGroupID()
        // The first two open tabs are one split.
        let browser = makeBrowser { space in
            for i in 1...2 { space.tabs[i].splitGroupID = split }
        }
        let space = try XCTUnwrap(browser.selectedSpace)
        let ids = space.currentTabs.map(\.id)
        let first = try XCTUnwrap(browser.createTabFolder([ids[0]], in: space.id))
        let second = try XCTUnwrap(browser.createTabFolder([ids[2]], in: space.id))
        XCTAssertTrue(browser.fileTabs([ids[0]], matching: .init(space: space), into: second, location: .current))
        XCTAssertEqual(browser.selectedSpace?.currentTabs.map(\.id), [ids[2], ids[0], ids[1], ids[3]])
        XCTAssertEqual(
            browser.selectedSpace?.tabs.filter { $0.folderID == second }.map(\.id), [ids[2], ids[0], ids[1]])
        XCTAssertTrue(
            browser.selectedSpace?.folders.contains { $0.id == first } == true,
            "Empty folders remain containers in both sections")
        XCTAssertEqual(browser.selectedSpace?.splitGroupMembers(of: split).count, 2)
    }

    func testCurrentFoldersNestAndRejectCyclesAndStaleSubtreeDropsAtomically() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.selectedSpace)
        let ids = space.currentTabs.map(\.id)
        let first = try XCTUnwrap(browser.createTabFolder([ids[0]], in: space.id))
        let second = try XCTUnwrap(browser.createTabFolder([ids[1]], in: space.id))
        XCTAssertTrue(browser.moveFolder(second, matching: .init(space: space), to: .current, into: first))
        let before = browser.session
        XCTAssertFalse(browser.moveFolder(first, matching: .init(space: space), to: .current, into: second))
        XCTAssertFalse(browser.moveFolder(first, matching: .init(space: space), to: .saved, before: FolderID()))
        let stale = BrowserSidebarReorderItem.folder(
            .init(folderID: first, spaceID: space.id, profileID: space.profile.id, memberTabIDs: [ids[0]]))
        XCTAssertFalse(
            BrowserSidebarReorderCommit(browser: browser, spaceAccess: BrowserSpaceAccessController()).apply(
                .init(kind: .insert(section: .folders(parentID: nil), beforeID: nil, index: 0)), for: stale))
        XCTAssertEqual(browser.session, before)
    }

    func testNestedCurrentFoldersSyncToAnotherDeviceWithMetadataAndMembership() throws {
        let root = BrowserFolder(
            title: "Research", location: .current, color: .ocean, isCollapsed: true,
            collapseModifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let nested = BrowserFolder(title: "Nested", location: .current, color: .rose, parentID: root.id)
        let child = nested.id
        let browser = makeBrowser { space in
            space.folders = [root, nested]
            space.tabs[1].folderID = child
        }
        let space = try XCTUnwrap(browser.selectedSpace)
        let payloads = try BrowserCoreSync.project(browser.session, preferences: .default, records: [])
        let records = payloads.map { BrowserSyncRecord.save($0, version: .init(logicalClock: 1, deviceID: UUID())) }
        for record in records { try record.validate() }
        let remote = try BrowserCoreSync.materialize(.freshInstallSeed, preferences: .default, records: records)
        let restored = try XCTUnwrap(remote.space(id: space.id))
        XCTAssertEqual(restored.folders, browser.session.spaces[0].folders)
        XCTAssertEqual(restored.tabs.first { $0.id == space.currentTabs[0].id }?.folderID, child)
        XCTAssertEqual(restored.tabs.first { $0.id == space.currentTabs[0].id }?.placement, .current)
    }

    func testEmptyFolderAndSavedFolderDefaultsSurviveEncoding() throws {
        let folder = BrowserFolder(title: "Empty", location: .current)
        XCTAssertEqual(try JSONDecoder().decode(BrowserFolder.self, from: JSONEncoder().encode(folder)), folder)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(folder)) as? [String: Any])
        object.removeValue(forKey: "location")
        let legacy = try JSONDecoder().decode(BrowserFolder.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.location, .saved)
        XCTAssertEqual(legacy.id, folder.id)
    }

    func testSyncPreferencesIncludeEachFolderWithItsSectionAndPreserveDisabledLocalSections() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.selectedSpace)
        let saved = try XCTUnwrap(browser.addFolder(title: "Saved", in: space.id))
        let current = try XCTUnwrap(browser.createTabFolder([space.currentTabs[0].id], in: space.id))
        var preferences = BrowserSyncPreferences.default
        preferences.currentTabs = false
        let payloads = try BrowserCoreSync.project(browser.session, preferences: preferences, records: [])
        let folderIDs = payloads.compactMap { payload -> FolderID? in
            if case .folder(let folder) = payload { return folder.id }
            return nil
        }
        XCTAssertEqual(folderIDs, [saved])
        let records = payloads.map { BrowserSyncRecord.save($0, version: .init(logicalClock: 1, deviceID: UUID())) }
        let refreshed = try BrowserCoreSync.materialize(browser.session, preferences: preferences, records: records)
        XCTAssertTrue(refreshed.spaces[0].folders.contains { $0.id == current && $0.location == .current })
        XCTAssertEqual(refreshed.spaces[0].tabs.first { $0.id == space.currentTabs[0].id }?.folderID, current)
    }

    func testPortableArchivePreservesCurrentFolderHierarchyAndContents() throws {
        let root = BrowserFolder(title: "Root", location: .current)
        let child = BrowserFolder(title: "Child", location: .current, parentID: root.id)
        let browser = makeBrowser { space in
            space.folders = [root, child]
            space.tabs[1].folderID = child.id
        }
        let space = try XCTUnwrap(browser.selectedSpace)
        let archive = BrowserPortableArchive(session: browser.session)
        let restored = try JSONDecoder().decode(BrowserPortableArchive.self, from: JSONEncoder().encode(archive))
            .materialize()
        let imported = try XCTUnwrap(restored.spaces.first)
        let importedRoot = try XCTUnwrap(imported.folders.first { $0.title == "Root" })
        let importedChild = try XCTUnwrap(imported.folders.first { $0.title == "Child" })
        XCTAssertEqual(importedChild.parentID, importedRoot.id)
        XCTAssertTrue(imported.folders.allSatisfy { $0.location == .current })
        XCTAssertEqual(imported.tabs.first { $0.title == space.currentTabs[0].title }?.folderID, importedChild.id)
    }

    /// One saved tab followed by four open tabs, showing the last one.
    private func makeBrowser(_ configure: (inout BrowserSpace) -> Void = { _ in }) -> BrowserStore {
        var space = BrowserSession.makeBlankSpace(number: 1)
        space.tabs = (0..<5).map { i in
            BrowserTab(
                id: TabID(), title: "Tab \(i)", url: URL(string: "https://example.com/\(i)"),
                symbol: "globe", placement: i == 0 ? .saved : .current)
        }
        configure(&space)
        return makeStore(space, showing: space.tabs[4].id)
    }

    /// A window showing `tabID` in the only Space.
    private func makeStore(_ space: BrowserSpace, showing tabID: TabID) -> BrowserStore {
        BrowserStore(
            session: BrowserSession(spaces: [space]),
            showing: space.id, tabs: [space.id: tabID])
    }
}
