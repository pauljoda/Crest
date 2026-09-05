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
                    space.selectedTabID = firstTab.id
                    let browser = BrowserStore(
                        session: .init(spaces: [space], selectedSpaceID: space.id),
                        persistence: InMemoryBrowserSessionPersistence())
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
                    XCTAssertEqual(result.selectedTabID, firstTab.id)
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
                    space.selectedTabID = moving.id
                    let browser = BrowserStore(
                        session: .init(spaces: [space], selectedSpaceID: space.id),
                        persistence: InMemoryBrowserSessionPersistence())
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
                    XCTAssertEqual(result.selectedTabID, moving.id)
                    XCTAssertEqual(
                        BrowserSidebarFolderListItem.items(
                            tabs: result.tabs, tree: result.folderTree,
                            location: location, parentID: parent?.id
                        ).map(\.id), [.folder(first.id), .tab(moving.id), .folder(second.id)])
                    let records = try BrowserSyncProjection.payloads(
                        from: browser.session, preferences: .default, existingRecords: []
                    ).map { BrowserSyncRecord.save($0, version: .init(logicalClock: 1, deviceID: UUID())) }
                    let synced = try BrowserSyncMaterializer.materialize(
                        records: records, preferences: .default, localSession: .freshInstallSeed)
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
            let browser = BrowserStore(
                session: .init(spaces: [space], selectedSpaceID: space.id),
                persistence: InMemoryBrowserSessionPersistence())
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
            for operation in ["delete", "close", "extensionClose", "move", "pin", "extensionMove"] {
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
                space.selectedTabID = after.id
                var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
                switch operation {
                case "delete": XCTAssertTrue(session.deleteTab(moving.id, in: space.id))
                case "close": session.closeTab(moving.id)
                case "extensionClose": XCTAssertTrue(session.closeExtensionTab(moving.id, in: space.id))
                case "move": XCTAssertTrue(session.moveTab(moving.id, to: .current))
                case "extensionMove": XCTAssertTrue(session.moveExtensionTabs([moving.id], in: space.id, to: -1))
                default: XCTAssertTrue(session.setExtensionTabPinned(true, tabID: moving.id, in: space.id))
                }
                let result = try XCTUnwrap(session.space(id: space.id))
                // An extension deliberately moving a singleton group carries
                // the folder itself, unlike moving its tab out through the UI.
                if operation != "extensionMove" || initiallyEmpty {
                    XCTAssertEqual(
                        BrowserSidebarFolderListItem.items(
                            tabs: result.tabs, tree: result.folderTree, location: .current
                        ).first?.id, .folder(folder.id), operation)
                }
            }
        }
    }

    func testPortableArchiveRebasesEmptyFolderBoundaryToImportedTabIDs() throws {
        var space = BrowserSession.makeBlankSpace(number: 1)
        let tab = BrowserTab(title: "After", url: URL(string: "https://example.com"), placement: .current)
        let folder = BrowserFolder(title: "Before", location: .current, orderAnchorTabID: tab.id)
        space.tabs = [tab]
        space.folders = [folder]
        space.selectedTabID = tab.id
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
            space.selectedTabID = members[0].id
            let browser = BrowserStore(
                session: .init(spaces: [space], selectedSpaceID: space.id),
                persistence: InMemoryBrowserSessionPersistence())
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
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        XCTAssertTrue(
            session.fileTabs([moving.id], in: space.id, into: nil, location: .current, beforeFolderID: populated.id))
        let result = try XCTUnwrap(session.space(id: space.id))
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
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        XCTAssertTrue(
            session.fileTabs([moving.id], in: space.id, into: nil, location: .saved, beforeFolderID: second.id))
        XCTAssertEqual(session.space(id: space.id)?.tabs.map(\.id), [moving.id, current.id])
    }

    func testUIAndExtensionShareRestoredNamesColorsAndOrderedMembershipAcrossWindows() throws {
        let browser = makeBrowser()
        let other = browser.makeWindowStore()
        let space = try XCTUnwrap(browser.selectedSpace)
        let tabs = space.currentTabs.map(\.id)
        let id = try XCTUnwrap(other.createTabFolder([tabs[0], tabs[2]], in: space.id))
        XCTAssertEqual(browser.selectedSpace?.currentTabs.map(\.id), [tabs[0], tabs[2], tabs[1], tabs[3]])
        XCTAssertTrue(other.extensionTabGroups === browser.extensionTabGroups)
        let group = try XCTUnwrap(browser.extensionTabGroups.groups(in: space.id).first { $0.folderID == id })
        _ = try browser.extensionTabGroups.update(
            group.id, in: space.id, title: "Claude Research", color: .orange, isCollapsed: true)
        XCTAssertEqual(browser.selectedSpace?.folders.first { $0.id == id }?.title, "Claude Research")
        let restored = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(browser.session))
        XCTAssertEqual(restored, browser.session)
        XCTAssertEqual(restored.space(id: space.id)?.tabs.filter { $0.folderID == id }.map(\.id), [tabs[0], tabs[2]])
    }

    func testPromotionKeepsTheExistingFolderIdentity() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.selectedSpace)
        let id = try XCTUnwrap(browser.createTabFolder([space.currentTabs[0].id], in: space.id))
        let group = try XCTUnwrap(browser.extensionTabGroups.groups(in: space.id).first)
        XCTAssertTrue(browser.moveFolder(id, matching: .init(space: space), to: .saved))
        XCTAssertEqual(browser.selectedSpace?.folders.first { $0.id == id }?.location, .saved)
        XCTAssertEqual(browser.extensionTabGroups.groups(in: space.id).first?.id, group.id)
    }

    func testSavedSubtreeMovesBothDirectionsAndRestoresWithoutLosingIdentityOrSplitMembership() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.selectedSpace)
        let root = try XCTUnwrap(browser.session.addFolder(title: "🧪 Research", color: .ocean, in: space.id))
        let child = try XCTUnwrap(browser.session.addFolder(title: "Child", color: .rose, parentID: root, in: space.id))
        let split = SplitGroupID()
        let ids = Array(space.tabs.prefix(2).map(\.id))
        for i in browser.session.spaces[0].tabs.indices where ids.contains(browser.session.spaces[0].tabs[i].id) {
            browser.session.spaces[0].tabs[i].placement = .saved
            browser.session.spaces[0].tabs[i].folderID = child
            browser.session.spaces[0].tabs[i].splitGroupID = split
        }
        _ = browser.session.setFolderCollapsed(child, in: space.id, isCollapsed: true)
        browser.persist(scope: .core)
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
        restored.repairRuntimeIntegrity()
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
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.selectedSpace)
        let ids = space.currentTabs.map(\.id)
        let split = SplitGroupID()
        for i in browser.session.spaces[0].tabs.indices
        where ids.prefix(2).contains(browser.session.spaces[0].tabs[i].id) {
            browser.session.spaces[0].tabs[i].splitGroupID = split
        }
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

    func testLegacyExtensionFoldersMigrateOnceIntoTheSharedTree() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.selectedSpace)
        let id = FolderID()
        let legacy = BrowserExtensionTabGroup(
            id: .init(rawValue: 42), folderID: id, spaceID: space.id,
            tabs: Array(space.currentTabs.prefix(2).map(\.id)), title: "Legacy", color: .orange, isCollapsed: true)
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(browser.session)) as? [String: Any])
        document["currentTabFolders"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([legacy]))
        var migrated = try JSONDecoder().decode(
            BrowserSession.self, from: JSONSerialization.data(withJSONObject: document))
        migrated.repairRuntimeIntegrity()
        XCTAssertEqual(migrated.spaces[0].folders.first?.id, id)
        XCTAssertEqual(migrated.spaces[0].folders.first?.location, .current)
        XCTAssertEqual(migrated.spaces[0].folders.first?.color, legacy.color.brandColor)
        XCTAssertEqual(migrated.spaces[0].tabs.filter { $0.folderID == id }.map(\.id), legacy.tabs)
        let encoded = try JSONEncoder().encode(migrated)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["currentTabFolders"])
        XCTAssertEqual(try JSONDecoder().decode(BrowserSession.self, from: encoded), migrated)
    }

    func testNestedCurrentFoldersSyncToAnotherDeviceWithMetadataAndMembership() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.selectedSpace)
        let root = try XCTUnwrap(
            browser.session.addFolder(title: "Research", color: .ocean, location: .current, in: space.id))
        let child = try XCTUnwrap(
            browser.session.addFolder(title: "Nested", color: .rose, parentID: root, in: space.id))
        XCTAssertTrue(
            browser.session.fileTabs([space.currentTabs[0].id], in: space.id, into: child, location: .current))
        _ = browser.session.setFolderCollapsed(root, in: space.id, isCollapsed: true)
        let payloads = try BrowserSyncProjection.payloads(
            from: browser.session, preferences: .default, existingRecords: [])
        let codec = BrowserCloudRecordCodec()
        let records = try payloads.map {
            let record = BrowserSyncRecord.save($0, version: .init(logicalClock: 1, deviceID: UUID()))
            return try codec.decode(codec.encode(record))
        }
        for record in records { try record.validate() }
        let remote = try BrowserSyncMaterializer.materialize(
            records: records, preferences: .default, localSession: .freshInstallSeed)
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
        let saved = try XCTUnwrap(browser.session.addFolder(title: "Saved", in: space.id))
        let current = try XCTUnwrap(browser.session.createTabFolder([space.currentTabs[0].id], in: space.id))
        var preferences = BrowserSyncPreferences.default
        preferences.currentTabs = false
        let payloads = try BrowserSyncProjection.payloads(
            from: browser.session, preferences: preferences, existingRecords: [])
        let folderIDs = payloads.compactMap { payload -> FolderID? in
            if case .folder(let folder) = payload { return folder.id }
            return nil
        }
        XCTAssertEqual(folderIDs, [saved])
        let codec = BrowserCloudRecordCodec()
        let records = try payloads.map {
            let record = BrowserSyncRecord.save($0, version: .init(logicalClock: 1, deviceID: UUID()))
            return try codec.decode(codec.encode(record))
        }
        let refreshed = try BrowserSyncMaterializer.materialize(
            records: records, preferences: preferences, localSession: browser.session)
        XCTAssertTrue(refreshed.spaces[0].folders.contains { $0.id == current && $0.location == .current })
        XCTAssertEqual(refreshed.spaces[0].tabs.first { $0.id == space.currentTabs[0].id }?.folderID, current)
    }

    func testPortableArchivePreservesCurrentFolderHierarchyAndContents() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.selectedSpace)
        let root = try XCTUnwrap(browser.session.addFolder(title: "Root", location: .current, in: space.id))
        let child = try XCTUnwrap(browser.session.addFolder(title: "Child", parentID: root, in: space.id))
        _ = browser.session.fileTabs([space.currentTabs[0].id], in: space.id, into: child, location: .current)
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

    func testFolderMovePublishesItsNewPositionToExtensions() async throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.selectedSpace)
        let id = try XCTUnwrap(browser.createTabFolder([space.currentTabs[0].id], in: space.id))
        let client = BrowserExtensionServiceClientID("move-test")!
        browser.extensionTabGroups.register(client: client, spaceID: space.id)
        var events = browser.extensionTabGroups.events(for: client).makeAsyncIterator()
        XCTAssertTrue(browser.moveFolder(id, matching: .init(space: space), to: .current))
        let moved = await events.next()
        XCTAssertEqual(moved?.kind, .moved)
        XCTAssertEqual(moved?.group.folderID, id)
    }

    private func makeBrowser() -> BrowserStore {
        var space = BrowserSession.makeBlankSpace(number: 1)
        space.tabs = (0..<5).map { i in
            BrowserTab(
                id: TabID(), title: "Tab \(i)", url: URL(string: "https://example.com/\(i)"),
                symbol: "globe", placement: i == 0 ? .saved : .current)
        }
        space.selectedTabID = space.tabs.last?.id
        return BrowserStore(
            session: .init(spaces: [space], selectedSpaceID: space.id), persistence: InMemoryBrowserSessionPersistence()
        )
    }
}
