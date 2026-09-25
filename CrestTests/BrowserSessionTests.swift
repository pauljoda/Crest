import XCTest

@testable import Crest

@MainActor
final class BrowserSessionTests: XCTestCase {
    func testLegacySpaceWithoutHistoryDecodesWithEmptyHistory() throws {
        let space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        let encoded = try JSONEncoder().encode(space)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "history")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserSpace.self, from: legacyData)

        XCTAssertTrue(decoded.history.isEmpty)
    }

    func testTabSectionsPartitionLargeFolderedSpaceInOneStableOrder() {
        let firstFolderID = FolderID()
        let secondFolderID = FolderID()
        let tabs = (0..<240).map { index in
            let placement: TabPlacement
            let folderID: FolderID?
            switch index % 6 {
            case 0:
                placement = .pinned
                folderID = nil
            case 1, 2:
                placement = .saved
                folderID = firstFolderID
            case 3:
                placement = .saved
                folderID = secondFolderID
            case 4:
                placement = .saved
                folderID = nil
            default:
                placement = .current
                folderID = nil
            }
            return BrowserTab(
                title: "Tab \(index)",
                url: URL(string: "https://example.com/\(index)"),
                placement: placement,
                folderID: folderID
            )
        }

        let sections = BrowserTabSections(tabs: tabs)

        XCTAssertEqual(sections.pinnedTabs.map(\.id), tabs.filter { $0.placement == .pinned }.map(\.id))
        XCTAssertEqual(
            sections.savedTabs(in: firstFolderID).map(\.id),
            tabs.filter { $0.placement == .saved && $0.folderID == firstFolderID }.map(\.id)
        )
        XCTAssertEqual(
            sections.savedTabs(in: secondFolderID).map(\.id),
            tabs.filter { $0.placement == .saved && $0.folderID == secondFolderID }.map(\.id)
        )
        XCTAssertEqual(
            sections.unfiledSavedTabs.map(\.id),
            tabs.filter { $0.placement == .saved && $0.folderID == nil }.map(\.id)
        )
        XCTAssertEqual(sections.currentTabs.map(\.id), tabs.filter { $0.placement == .current }.map(\.id))
        XCTAssertTrue(sections.savedTabs(in: FolderID()).isEmpty)
    }

    func testStartPageDraftsAreNotPresentedAsSidebarTabs() {
        let website = BrowserTab(
            title: "WebKit",
            url: URL(string: "https://webkit.org"),
            placement: .current
        )
        let draft = BrowserTab.startPage()
        let sections = BrowserTabSections(tabs: [website, draft])

        XCTAssertEqual(sections.currentTabs.map(\.id), [website.id, draft.id])
        XCTAssertEqual(sections.sidebarCurrentTabs.map(\.id), [website.id])
    }

    func testPopupCloseCannotRemovePinnedTab() throws {
        let store = makeStore(.preview)
        let space = try XCTUnwrap(store.selectedSpace)
        let pinned = try XCTUnwrap(space.pinnedTabs.first)
        store.selectTab(pinned.id)
        XCTAssertEqual(store.selectedTab?.id, pinned.id)

        // `window.close()` reaches the store through this path.
        XCTAssertFalse(store.closeTab(pinned.id, in: space.id))

        let updated = try XCTUnwrap(store.session.space(id: space.id))
        XCTAssertTrue(updated.contains(pinned.id))
        XCTAssertFalse(updated.archivedTabs.contains { $0.id == pinned.id })
        XCTAssertEqual(store.selectedTabID(in: space.id), pinned.id)
    }

    func testSwitchingSpacesRestoresEachSpacesSelectedTab() throws {
        let store = makeStore(.preview)
        let work = try XCTUnwrap(store.session.spaces.first)
        let personal = try XCTUnwrap(store.session.spaces.last)
        let workTabID = try XCTUnwrap(work.savedTabs.first?.id)
        let personalTabID = try XCTUnwrap(personal.pinnedTabs.last?.id)
        XCTAssertEqual(store.selectedSpaceID, work.id)

        store.selectTab(workTabID)
        store.selectSpace(personal.id)
        store.selectTab(personalTabID)
        store.selectSpace(work.id)

        XCTAssertEqual(store.selectedTab?.id, workTabID)

        store.selectSpace(personal.id)
        XCTAssertEqual(store.selectedTab?.id, personalTabID)
    }

    func testRestoringAnArchivedTabReturnsItOnlyToItsSpaceAndSelectsIt() throws {
        let store = makeStore(.cleanupFixture(now: .now))
        let personalID = try XCTUnwrap(store.session.spaces.last?.id)

        store.sweepExpiredBrowsingData()
        let archivedBeforeRestore = try XCTUnwrap(store.selectedSpace).archivedTabs
        let archivedID = try XCTUnwrap(archivedBeforeRestore.first?.id)
        store.restoreArchivedTab(archivedID)

        let space = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(store.selectedTab?.id, archivedID)
        XCTAssertEqual(store.selectedTab?.placement, .current)
        XCTAssertTrue(space.currentTabs.contains { $0.id == archivedID })
        XCTAssertFalse(space.archivedTabs.contains { $0.id == archivedID })
        XCTAssertEqual(space.archivedTabs.count, archivedBeforeRestore.count - 1)
        XCTAssertTrue(try XCTUnwrap(store.session.space(id: personalID)).archivedTabs.isEmpty)
    }

    func testClosingAStartPageDraftNeverAddsItToTheArchive() throws {
        let store = makeStore(.preview)
        let space = try XCTUnwrap(store.selectedSpace)
        let startPage = try XCTUnwrap(space.currentTabs.first(where: \.isStartPage))
        let archivedIDsBeforeClosing = space.archivedTabs.map(\.id)

        XCTAssertTrue(store.closeTab(startPage.id, in: space.id))

        let updatedSpace = try XCTUnwrap(store.session.space(id: space.id))
        XCTAssertFalse(updatedSpace.contains(startPage.id))
        XCTAssertEqual(updatedSpace.archivedTabs.map(\.id), archivedIDsBeforeClosing)
        XCTAssertFalse(updatedSpace.archivedTabs.contains { $0.tab.isStartPage })
    }

    func testRuntimeRepairDropsLegacyStartPageDraftsFromTheArchive() throws {
        var session = BrowserSession.preview
        session.spaces[0].archivedTabs = [
            ArchivedTab(
                tab: BrowserTab.startPage(),
                archivedAt: .distantPast,
                reason: .closed
            ),
            ArchivedTab(
                tab: BrowserTab(
                    title: "Recoverable",
                    url: URL(string: "https://example.com/recoverable"),
                    placement: .current
                ),
                archivedAt: .distantPast,
                reason: .closed
            ),
        ]

        session = try session.openedAsSeed()

        let archive = try XCTUnwrap(session.spaces.first).archivedTabs
        XCTAssertEqual(archive.map(\.tab.title), ["Recoverable"])
        XCTAssertFalse(archive.contains { $0.tab.isStartPage })
    }

    func testLegacySpaceWithoutArchiveDecodesWithEmptyArchive() throws {
        let space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        let encoded = try JSONEncoder().encode(space)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "archivedTabs")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserSpace.self, from: legacyData)

        XCTAssertTrue(decoded.archivedTabs.isEmpty)
    }

    func testLegacySpaceWithoutBrowsingPreferencesUsesSafeDefaults() throws {
        let space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        let encoded = try JSONEncoder().encode(space)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "browsingPreferences")
        object.removeValue(forKey: "isSavedTabsExpanded")
        object.removeValue(forKey: "savedTabsExpansionModifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserSpace.self, from: legacyData)

        XCTAssertEqual(decoded.browsingPreferences, .default)
        XCTAssertTrue(decoded.isSavedTabsExpanded)
        XCTAssertNil(decoded.savedTabsExpansionModifiedAt)
    }

    func testLegacyTabWithoutPositionTimestampStillDecodes() throws {
        let tab = BrowserTab(
            title: "Legacy",
            url: URL(string: "https://example.com"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 100)
        )
        let encoded = try JSONEncoder().encode(tab)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "positionModifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserTab.self, from: legacyData)

        XCTAssertNil(decoded.positionModifiedAt)
    }

    func testLegacyTabWithoutKeepLoadedStateDefaultsToAutomaticResidency() throws {
        let tab = BrowserTab(
            title: "Legacy",
            url: URL(string: "https://example.com"),
            placement: .saved,
            keepsPageLoaded: true
        )
        let encoded = try JSONEncoder().encode(tab)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "keepsPageLoaded")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserTab.self, from: legacyData)

        XCTAssertFalse(decoded.keepsPageLoaded)
    }

    func testRenamingATabWinsOverThePageTitleUntilItIsCleared() throws {
        let store = makeStore(.preview)
        let spaceID = store.selectedSpaceID
        let tabID = try XCTUnwrap(
            store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com/docs")))
        )
        let pageTitle = try XCTUnwrap(store.selectedTab?.title)

        XCTAssertTrue(store.setTabCustomTitle("  Release Notes  ", for: tabID, in: spaceID))

        let renamed = try XCTUnwrap(store.selectedTab)
        XCTAssertEqual(renamed.customTitle, "Release Notes")
        XCTAssertEqual(renamed.displayTitle, "Release Notes")
        XCTAssertEqual(
            renamed.title,
            pageTitle,
            "A rename layers over the page title instead of replacing it."
        )
        let renamedAt = try XCTUnwrap(renamed.titleModifiedAt)

        XCTAssertFalse(
            store.setTabCustomTitle("Release Notes", for: tabID, in: spaceID),
            "Re-committing the same name is not a change."
        )
        XCTAssertEqual(store.selectedTab?.titleModifiedAt, renamedAt)

        XCTAssertTrue(store.setTabCustomTitle("", for: tabID, in: spaceID))
        let cleared = try XCTUnwrap(store.selectedTab)
        XCTAssertNil(cleared.customTitle)
        XCTAssertEqual(cleared.displayTitle, pageTitle)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(cleared.titleModifiedAt), renamedAt)
    }

    func testKeepLoadedCanBeEnabledAndRemovedWithoutChangingTheTabPlacement() throws {
        let store = makeStore(.preview)
        let spaceID = store.selectedSpaceID
        let tabID = try XCTUnwrap(store.selectedTab?.id)
        let placement = try XCTUnwrap(store.selectedTab?.placement)

        XCTAssertTrue(store.setTabKeepsPageLoaded(true, for: tabID, in: spaceID))
        XCTAssertEqual(store.selectedTab?.keepsPageLoaded, true)
        XCTAssertEqual(store.selectedTab?.placement, placement)
        XCTAssertFalse(store.setTabKeepsPageLoaded(true, for: tabID, in: spaceID))
        XCTAssertTrue(store.setTabKeepsPageLoaded(false, for: tabID, in: spaceID))
        XCTAssertEqual(store.selectedTab?.keepsPageLoaded, false)
        XCTAssertEqual(store.selectedTab?.placement, placement)
    }

    func testRenamingATabDoesNotClaimANewerPositionChange() throws {
        let store = makeStore(.preview)
        let spaceID = store.selectedSpaceID
        let tabID = try XCTUnwrap(store.selectedTab?.id)
        XCTAssertTrue(store.moveTab(tabID, to: .pinned))
        let movedAt = try XCTUnwrap(store.selectedTab?.positionModifiedAt)

        XCTAssertTrue(store.setTabCustomTitle("Inbox", for: tabID, in: spaceID))

        XCTAssertEqual(store.selectedTab?.positionModifiedAt, movedAt)
        XCTAssertNotNil(store.selectedTab?.titleModifiedAt)
    }

    func testTabWrittenBeforeRenamingDecodesWithoutACustomTitle() throws {
        let tabID = try XCTUnwrap(UUID(uuidString: "F0000000-0000-0000-0000-000000000001"))
        let json = """
            {
              "id": {"rawValue": "\(tabID.uuidString)"},
              "title": "Docs",
              "url": "https://example.com/docs",
              "savedURL": "https://example.com/docs",
              "symbol": "globe",
              "placement": "saved",
              "lastActivatedAt": 100,
              "positionModifiedAt": 200
            }
            """

        let decoded = try JSONDecoder().decode(
            BrowserTab.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(decoded.id, tabID)
        XCTAssertEqual(decoded.title, "Docs")
        XCTAssertNil(decoded.customTitle)
        XCTAssertNil(decoded.titleModifiedAt)
        XCTAssertEqual(decoded.displayTitle, "Docs")
        XCTAssertEqual(decoded.lastActivatedAt, Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertEqual(
            decoded.positionModifiedAt,
            Date(timeIntervalSinceReferenceDate: 200)
        )
    }

    func testARenamedTabRoundTripsThroughTheSessionJSON() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.spaces.first?.id)
        let renamedAt = Date(timeIntervalSince1970: 4_000)
        let renamed = BrowserTab(
            title: "Docs",
            url: URL(string: "https://example.com/docs"),
            placement: .current,
            customTitle: "Release Notes",
            titleModifiedAt: renamedAt
        )
        session.spaces[0].tabs.append(renamed)

        var decoded = try JSONDecoder().decode(
            BrowserSession.self,
            from: try JSONEncoder().encode(session)
        )
        decoded = try decoded.openedAsSeed()

        let tab = try XCTUnwrap(
            decoded.space(id: spaceID)?.tabs.first(where: { $0.id == renamed.id })
        )
        XCTAssertEqual(tab.customTitle, "Release Notes")
        XCTAssertEqual(tab.titleModifiedAt, renamedAt)
        XCTAssertEqual(tab.displayTitle, "Release Notes")
    }

    func testSpaceCapsPinnedGridAtTwelveTabs() throws {
        let store = makeStore(.preview)
        let limit = TabPlacement.pinnedCapacity

        for index in 0..<limit {
            guard try XCTUnwrap(store.selectedSpace).pinnedTabs.count < limit else { break }
            store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com/pin-\(index)")))
            store.pinSelectedTab()
        }
        XCTAssertEqual(try XCTUnwrap(store.selectedSpace).pinnedTabs.count, limit)

        let overflowID = try XCTUnwrap(
            store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com/thirteenth-pin")))
        )
        store.pinSelectedTab()

        let space = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(space.pinnedTabs.count, limit)
        XCTAssertEqual(space.tabs.first(where: { $0.id == overflowID })?.placement, .current)
    }

    func testTabMoveReordersWithinASectionWithoutChangingSelection() throws {
        let store = makeStore(.preview)
        let olderID = try XCTUnwrap(
            store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com/older")))
        )
        let newestID = try XCTUnwrap(
            store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com/newest")))
        )
        let firstCurrentID = try XCTUnwrap(store.selectedSpace?.currentTabs.first?.id)
        XCTAssertNotEqual(firstCurrentID, olderID)

        XCTAssertTrue(store.moveTab(olderID, to: .current, before: firstCurrentID))

        let space = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(Array(space.currentTabs.prefix(2)).map(\.id), [olderID, firstCurrentID])
        XCTAssertEqual(store.selectedTab?.id, newestID)
        XCTAssertNotNil(space.tabs.first(where: { $0.id == olderID })?.positionModifiedAt)
    }

    func testTabActivationDoesNotClaimANewerPositionChange() throws {
        let store = makeStore(.preview)
        let tabID = try XCTUnwrap(store.selectedTab?.id)
        XCTAssertTrue(store.moveTab(tabID, to: .pinned))
        let positionModifiedAt = try XCTUnwrap(store.selectedTab?.positionModifiedAt)

        store.selectTab(tabID)

        XCTAssertEqual(store.selectedTab?.positionModifiedAt, positionModifiedAt)
    }

    func testTabMoveChangesDurabilityAndFolderWithoutChangingIdentity() throws {
        let store = makeStore(.preview)
        let tabID = try XCTUnwrap(
            store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com")))
        )
        let folderID = try XCTUnwrap(store.selectedSpace?.folders.first?.id)

        XCTAssertTrue(store.moveTab(tabID, to: .saved, folderID: folderID))
        XCTAssertEqual(store.selectedTab?.id, tabID)
        XCTAssertEqual(store.selectedTab?.placement, .saved)
        XCTAssertEqual(store.selectedTab?.folderID, folderID)

        XCTAssertTrue(store.moveTab(tabID, to: .pinned))
        XCTAssertEqual(store.selectedTab?.id, tabID)
        XCTAssertEqual(store.selectedTab?.placement, .pinned)
        XCTAssertNil(store.selectedTab?.folderID)

        XCTAssertTrue(store.moveTab(tabID, to: .current))
        XCTAssertEqual(store.selectedTab?.id, tabID)
        XCTAssertEqual(store.selectedTab?.placement, .current)
    }

    func testDeletionArchiveRoundTripsThroughRollbackCompatibleSessionTerms() throws {
        let archived = ArchivedTab(
            tab: BrowserTab(
                title: "Deleted",
                url: URL(string: "https://deleted.crest.test"),
                symbol: "trash",
                placement: .current
            ),
            archivedAt: Date(timeIntervalSince1970: 2_000),
            reason: .deleted
        )

        let data = try JSONEncoder().encode(archived)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let decoded = try JSONDecoder().decode(ArchivedTab.self, from: data)

        XCTAssertEqual(payload["reason"] as? String, "closed")
        XCTAssertEqual(payload["deletionOrigin"] as? String, "local")
        XCTAssertEqual(decoded, archived)
    }

    func testEmojiNormalizationKeepsOneCompleteGraphemeCluster() {
        XCTAssertEqual(
            BrowserIconSymbol.normalizedEmoji("👨🏽‍💻trailing text"),
            "👨🏽‍💻"
        )
        XCTAssertEqual(BrowserIconSymbol.normalizedEmoji("🇺🇸"), "🇺🇸")
        XCTAssertEqual(BrowserIconSymbol.normalizedEmoji("1️⃣"), "1️⃣")
        XCTAssertEqual(BrowserIconSymbol.normalizedEmoji("👩‍👩‍👧‍👦"), "👩‍👩‍👧‍👦")
        XCTAssertNil(BrowserIconSymbol.normalizedEmoji("ordinary text"))
    }

    func testComposedEmojiPersistsWithoutScalarTruncation() throws {
        var session = BrowserSession.preview
        let emoji = "👨🏽‍💻"
        let tab = BrowserTab(
            title: "Workbench",
            url: URL(string: "https://example.com/workbench"),
            symbol: BrowserTab.symbol(forEmoji: emoji),
            iconMode: .emoji,
            placement: .current
        )
        session.spaces[0].tabs.append(tab)

        let decoded = try JSONDecoder().decode(
            BrowserSession.self,
            from: JSONEncoder().encode(session)
        )
        let decodedTab = decoded.spaces.first?.tabs.first { $0.id == tab.id }
        XCTAssertEqual(decodedTab?.iconMode, .emoji)
        XCTAssertEqual(decodedTab?.emojiIcon, emoji)
        XCTAssertEqual(decodedTab?.emojiIcon?.count, 1)
    }

    func testFolderTreePreservesPreorderPathsAndAncestorDisclosure() throws {
        let root = BrowserFolder(title: "Projects")
        let child = BrowserFolder(title: "Crest", parentID: root.id)
        let grandchild = BrowserFolder(title: "Research", parentID: child.id)
        let sibling = BrowserFolder(title: "Travel")
        let tree = BrowserFolderTree(folders: [root, child, grandchild, sibling])

        XCTAssertTrue(tree.isValid)
        XCTAssertEqual(tree.foldersInDisplayOrder.map(\.id), [root.id, child.id, grandchild.id, sibling.id])
        XCTAssertEqual(tree.pathTitle(for: grandchild.id), "Projects › Crest › Research")
        XCTAssertEqual(tree.depth(of: grandchild.id), 2)
        XCTAssertEqual(
            tree.flattenedNodes(collapsedFolderIDs: [root.id]).map(\.id),
            [root.id, sibling.id]
        )
    }

    func testFolderCollapseStateChangesOnlyWhenNeeded() throws {
        let store = makeStore(.preview)
        let spaceID = store.selectedSpaceID
        let folderID = try XCTUnwrap(store.addFolder(in: spaceID))
        func folder() -> BrowserFolder? {
            store.session.space(id: spaceID)?.folders.first { $0.id == folderID }
        }

        XCTAssertTrue(store.setFolderCollapsed(folderID, in: spaceID, isCollapsed: true))
        XCTAssertEqual(folder()?.isCollapsed, true)
        let collapsedAt = try XCTUnwrap(folder()?.collapseModifiedAt)
        XCTAssertFalse(store.setFolderCollapsed(folderID, in: spaceID, isCollapsed: true))
        XCTAssertEqual(folder()?.collapseModifiedAt, collapsedAt)

        XCTAssertTrue(store.setFolderCollapsed(folderID, in: spaceID, isCollapsed: false))
        XCTAssertEqual(folder()?.isCollapsed, false)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(folder()?.collapseModifiedAt), collapsedAt)
    }

    func testSavedTabsExpansionStateChangesOnlyWhenNeeded() throws {
        let store = makeStore(.preview)
        let spaceID = store.selectedSpaceID
        func space() throws -> BrowserSpace { try XCTUnwrap(store.session.space(id: spaceID)) }

        XCTAssertTrue(store.setSavedTabsExpanded(false, in: spaceID))
        XCTAssertFalse(try space().isSavedTabsExpanded)
        let collapsedAt = try XCTUnwrap(try space().savedTabsExpansionModifiedAt)
        XCTAssertFalse(store.setSavedTabsExpanded(false, in: spaceID))
        XCTAssertEqual(try space().savedTabsExpansionModifiedAt, collapsedAt)

        XCTAssertTrue(store.setSavedTabsExpanded(true, in: spaceID))
        XCTAssertTrue(try space().isSavedTabsExpanded)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(try space().savedTabsExpansionModifiedAt), collapsedAt)
    }

    func testFolderDepthIsBoundedForCreationAndMovement() throws {
        let store = makeStore(.preview)
        let spaceID = store.selectedSpaceID
        var parentID: FolderID?
        for depth in 0..<BrowserSpace.maximumFolderDepth {
            parentID = try XCTUnwrap(
                store.addFolder(title: "Level \(depth)", parentID: parentID, in: spaceID)
            )
        }

        XCTAssertNil(store.addFolder(title: "Too Deep", parentID: parentID, in: spaceID))
        XCTAssertEqual(
            try XCTUnwrap(store.session.space(id: spaceID)).folderTree.depth(
                of: try XCTUnwrap(parentID)
            ),
            BrowserSpace.maximumFolderDepth - 1
        )
    }

    func testLegacyFolderWithoutParentDecodesAsTopLevel() throws {
        let source = BrowserFolder(title: "Legacy")
        let encoded = try JSONEncoder().encode(source)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "parentID")
        object.removeValue(forKey: "color")
        object.removeValue(forKey: "isCollapsed")
        object.removeValue(forKey: "collapseModifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserFolder.self, from: legacyData)

        XCTAssertNil(decoded.parentID)
        XCTAssertEqual(decoded.color, .folderDefault)
        XCTAssertFalse(decoded.isCollapsed)
        XCTAssertNil(decoded.collapseModifiedAt)
    }

    func testRuntimeRepairReidentifiesDuplicateProfilesAndTabsAcrossSpaces() throws {
        let sharedProfile = BrowsingProfile()
        let sharedTabID = TabID()
        let firstTab = BrowserTab(id: sharedTabID, title: "Work", url: nil, placement: .current)
        let secondTab = BrowserTab(id: sharedTabID, title: "Personal", url: nil, placement: .current)
        let first = BrowserSpace(
            id: SpaceID(),
            profile: sharedProfile,
            name: "Work",
            symbol: "briefcase",
            accent: .indigo,
            folders: [],
            tabs: [firstTab]
        )
        let second = BrowserSpace(
            id: SpaceID(),
            profile: sharedProfile,
            name: "Personal",
            symbol: "house",
            accent: .orange,
            folders: [],
            tabs: [secondTab]
        )

        let session = try BrowserSession(spaces: [first, second]).openedAsSeed()

        XCTAssertEqual(session.spaces.map(\.id), [first.id, second.id])
        XCTAssertEqual(Set(session.spaces.map(\.profile.id)).count, 2)
        XCTAssertEqual(Set(session.tabIDs).count, 2)
    }

    func testRuntimeRepairGivesEmptySessionsAndSpacesAUsableLaunchTab() throws {
        let emptySpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Empty",
            symbol: "circle",
            accent: .teal,
            folders: [],
            tabs: []
        )

        let session = try BrowserSession(spaces: [emptySpace]).openedAsSeed()

        let repaired = try XCTUnwrap(session.space(id: emptySpace.id))
        XCTAssertEqual(repaired.tabs.count, 1)
        let launch = BrowserStore(session: session)
        XCTAssertEqual(launch.selectedSpaceID, emptySpace.id)
        let launchTab = try XCTUnwrap(launch.selectedTab)
        XCTAssertEqual(launchTab.title, BrowserTab.startPageTitle)
        XCTAssertEqual(launchTab.symbol, BrowserTab.startPageSymbol)
        XCTAssertEqual(launchTab.placement, .current)

        let noSpaces = try BrowserSession(spaces: []).openedAsSeed()
        XCTAssertEqual(noSpaces.spaces.count, 1)
        XCTAssertNotNil(BrowserStore(session: noSpaces).selectedTab)
    }

    func testRuntimeRepairBoundsPinsHistoryFoldersAndArchivedIdentities() throws {
        let duplicateFolderID = FolderID()
        let cycleAID = FolderID()
        let cycleBID = FolderID()
        let folders = [
            BrowserFolder(id: duplicateFolderID, title: "First"),
            BrowserFolder(id: duplicateFolderID, title: "Second"),
            BrowserFolder(id: cycleAID, title: "Cycle A", parentID: cycleBID),
            BrowserFolder(id: cycleBID, title: "Cycle B", parentID: cycleAID),
            BrowserFolder(title: "Orphan", parentID: FolderID()),
        ]
        var tabs = (0..<14).map {
            BrowserTab(title: "Pinned \($0)", url: nil, placement: .pinned, folderID: duplicateFolderID)
        }
        let danglingFolderID = FolderID()
        tabs.append(BrowserTab(title: "Saved", url: nil, placement: .saved, folderID: danglingFolderID))
        let archivedCollision = ArchivedTab(
            tab: BrowserTab(
                id: tabs[0].id,
                title: "Archived",
                url: URL(string: "https://example.com/archived"),
                placement: .saved
            ),
            archivedAt: .distantPast,
            reason: .closed
        )
        let history = (0...BrowserSession.maximumHistoryEntriesPerSpace).map { index in
            BrowserHistoryEntry(
                url: URL(string: "https://example.com/\(index)")!,
                title: "Visit \(index)",
                firstVisitedAt: .distantPast,
                lastVisitedAt: .distantPast
            )
        }
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Hostile",
            symbol: "exclamationmark.shield",
            accent: .rose,
            folders: folders,
            tabs: tabs,
            archivedTabs: [archivedCollision],
            history: history
        )

        let session = try BrowserSession(spaces: [space]).openedAsSeed()

        let repaired = try XCTUnwrap(session.spaces.first)
        XCTAssertEqual(Set(repaired.folders.map(\.id)).count, 5)
        XCTAssertTrue(repaired.folderTree.isValid)
        XCTAssertTrue(
            repaired.folders.allSatisfy { folder in
                folder.parentID == nil || repaired.folders.contains { $0.id == folder.parentID }
            })
        XCTAssertEqual(repaired.pinnedTabs.count, TabPlacement.pinnedCapacity)
        XCTAssertTrue(repaired.tabs.filter { $0.placement != .saved }.allSatisfy { $0.folderID == nil })
        XCTAssertTrue(
            repaired.savedTabs.allSatisfy { tab in
                tab.folderID == nil || repaired.folders.contains { $0.id == tab.folderID }
            })
        XCTAssertEqual(repaired.history.count, BrowserSession.maximumHistoryEntriesPerSpace)
        XCTAssertEqual(repaired.archivedTabs.first?.tab.placement, .current)
        XCTAssertNil(repaired.archivedTabs.first?.tab.folderID)
        let archivedID = try XCTUnwrap(repaired.archivedTabs.first?.id)
        XCTAssertFalse(Set(repaired.tabs.map(\.id)).contains(archivedID))
    }

    // MARK: - Helpers

    /// A window store over `session` that opens on its launch Space.
    private func makeStore(_ session: BrowserSession) -> BrowserStore {
        BrowserStore(session: session)
    }
}

final class BrowserTabStateArchiveTests: XCTestCase {

    func testEngineStateRejectsOtherEnginesAndVersionsWhileKeepingLegacyWebKitArchives() throws {
        let payload = Data("opaque engine history".utf8)
        let chromium = try XCTUnwrap(BrowserEngineInteractionState(
            engine: .chromium, version: "1", payload: payload).encoded())
        let webkit = try XCTUnwrap(BrowserEngineInteractionState(
            engine: .webKit, version: "os-1", payload: payload).encoded())

        XCTAssertEqual(BrowserEngineInteractionState.payload(chromium, engine: .chromium, version: "1"), payload)
        XCTAssertEqual(BrowserEngineInteractionState.payload(webkit, engine: .webKit, version: "os-1"), payload)
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium, engine: .webKit, version: "1"))
        XCTAssertNil(BrowserEngineInteractionState.payload(webkit, engine: .chromium, version: "os-1"))
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium, engine: .chromium, version: "2"))
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium.dropLast(), engine: .chromium, version: "1"))
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium.dropLast(), engine: .webKit, version: "1"))
        XCTAssertEqual(BrowserEngineInteractionState.payload(payload, engine: .webKit, version: "os-1"), payload)
        XCTAssertNil(BrowserEngineInteractionState.payload(payload, engine: .chromium, version: "1"))
        XCTAssertNil(BrowserEngineInteractionState(engine: .chromium, version: "1", payload: Data()).encoded())
    }

    func testNamedReviewArchivesStaySeparateFromProductionAndEphemeralLaunches() throws {
        func environment(_ identity: String) -> BrowserLaunchEnvironment {
            BrowserLaunchEnvironment(values: ["CREST_ISOLATED_SESSION": "1",
                "CREST_ISOLATED_PERSISTENCE_ID": identity], isXCTestRuntime: false)
        }
        let first = try XCTUnwrap(BrowserTabStateArchive.forLaunch(environment("review-one")))
        let same = try XCTUnwrap(BrowserTabStateArchive.forLaunch(environment("review-one")))
        let other = try XCTUnwrap(BrowserTabStateArchive.forLaunch(environment("review-two")))
        XCTAssertEqual(first.rootDirectory, same.rootDirectory)
        XCTAssertNotEqual(first.rootDirectory, other.rootDirectory)
        XCTAssertNotEqual(first.rootDirectory, BrowserTabStateArchive.production()?.rootDirectory)
        XCTAssertNil(BrowserTabStateArchive.forLaunch(BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1"], isXCTestRuntime: false)))
        XCTAssertNil(BrowserTabStateArchive.forLaunch(BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_PERSISTENCE_ID": "review-one"], isXCTestRuntime: true)))
        XCTAssertNil(BrowserTabStateArchive.forLaunch(BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_PERSISTENCE_ID": "review-one"], isXCTestRuntime: false,
            isSwiftUIPreviewRuntime: true)))
    }

    func testStateFromAnotherOSBuildOrFormatIsNotRestorable() throws {
        let payload = Data("session".utf8)
        let foreignBuild = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(
                    interactionState: payload,
                    url: nil,
                    osBuild: "Version 1.0 (Build 0A0)"
                ).encoded()
            )
        )
        let foreignFormat = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(
                    interactionState: payload,
                    url: nil,
                    formatVersion: BrowserTabStateEnvelope.currentFormatVersion + 1
                ).encoded()
            )
        )

        XCTAssertFalse(
            foreignBuild.isRestorable,
            "interactionState is WebKit's private format, so another OS build must not be trusted."
        )
        XCTAssertFalse(foreignFormat.isRestorable)
    }

    func testUnframedOrTruncatedDataDecodesToNothing() throws {
        let encoded = BrowserTabStateEnvelope(
            interactionState: Data("session".utf8),
            url: try XCTUnwrap(URL(string: "https://example.com/"))
        ).encoded()

        XCTAssertNil(BrowserTabStateEnvelope.decode(Data()))
        XCTAssertNil(BrowserTabStateEnvelope.decode(Data("not an envelope at all".utf8)))
        XCTAssertNil(
            BrowserTabStateEnvelope.decode(encoded.prefix(8)),
            "A file cut short must not decode into a partial session."
        )
        XCTAssertNil(
            BrowserTabStateEnvelope.decode(encoded.dropLast(encoded.count - 14)),
            "A header promising more bytes than the file holds must be refused."
        )
    }

    func testRestorePolicyKeepsFragmentDriftAndRefusesADifferentDestination() throws {
        let archived = try XCTUnwrap(URL(string: "https://example.com/doc#section-2"))
        let sameDocument = try XCTUnwrap(URL(string: "https://example.com/doc"))
        let otherQuery = try XCTUnwrap(URL(string: "https://example.com/doc?revision=2"))
        let otherHost = try XCTUnwrap(URL(string: "https://elsewhere.example/doc"))

        XCTAssertTrue(
            BrowserTabStateRestorePolicy.restoresArchivedState(
                archivedURL: archived,
                tabURL: sameDocument
            )
        )
        XCTAssertTrue(
            BrowserTabStateRestorePolicy.restoresArchivedState(
                archivedURL: archived,
                tabURL: archived
            )
        )
        XCTAssertFalse(
            BrowserTabStateRestorePolicy.restoresArchivedState(
                archivedURL: archived,
                tabURL: otherQuery
            ),
            "A tab pointed somewhere else while unloaded must win over its old state."
        )
        XCTAssertFalse(
            BrowserTabStateRestorePolicy.restoresArchivedState(
                archivedURL: archived,
                tabURL: otherHost
            )
        )
        XCTAssertFalse(
            BrowserTabStateRestorePolicy.restoresArchivedState(
                archivedURL: nil,
                tabURL: sameDocument
            )
        )
    }

    func testArchivedStateIsReadableBackAndDeletablePerTab() async throws {
        let archive = try makeArchive()
        let profileID = UUID()
        let first = TabID()
        let second = TabID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))

        archive.archive(
            interactionState: Data("first".utf8),
            url: url,
            profileID: profileID,
            tabID: first
        )
        archive.archive(
            interactionState: Data("second".utf8),
            url: url,
            profileID: profileID,
            tabID: second
        )
        await archive.flushPendingWrites()

        XCTAssertEqual(
            BrowserTabStateEnvelope.decode(
                try XCTUnwrap(archive.archivedState(profileID: profileID, tabID: first))
            )?.interactionState,
            Data("first".utf8)
        )

        archive.removeState(profileID: profileID, tabID: first)
        await archive.flushPendingWrites()

        XCTAssertNil(archive.archivedState(profileID: profileID, tabID: first))
        XCTAssertNotNil(archive.archivedState(profileID: profileID, tabID: second))
    }

    func testAnEmptyStateIsNeverWritten() async throws {
        let archive = try makeArchive()
        let profileID = UUID()
        let tabID = TabID()

        archive.archive(
            interactionState: Data(),
            url: nil,
            profileID: profileID,
            tabID: tabID
        )
        await archive.flushPendingWrites()

        XCTAssertNil(archive.archivedState(profileID: profileID, tabID: tabID))
    }

    func testAnOversizedStateIsDroppedAndTakesAnyStaleStateWithIt() async throws {
        let archive = try makeArchive(maximumStateByteCount: 512)
        let profileID = UUID()
        let tabID = TabID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))

        archive.archive(
            interactionState: Data("small".utf8),
            url: url,
            profileID: profileID,
            tabID: tabID
        )
        await archive.flushPendingWrites()
        XCTAssertNotNil(archive.archivedState(profileID: profileID, tabID: tabID))

        archive.archive(
            interactionState: Data(repeating: 0xAB, count: 4096),
            url: url,
            profileID: profileID,
            tabID: tabID
        )
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: profileID, tabID: tabID),
            "An oversized state must not leave an older one behind to restore instead."
        )
    }

    func testAProfileKeepsOnlyItsMostRecentlyWrittenStates() async throws {
        let archive = try makeArchive(maximumStatesPerProfile: 3)
        let profileID = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))
        var tabIDs: [TabID] = []

        for index in 0..<5 {
            let tabID = TabID()
            tabIDs.append(tabID)
            archive.archive(
                interactionState: Data("state-\(index)".utf8),
                url: url,
                profileID: profileID,
                tabID: tabID
            )
            await archive.flushPendingWrites()
            // Modification dates order the eviction, and APFS timestamps are not
            // fine-grained enough to separate writes issued back to back.
            try await Task.sleep(for: .milliseconds(20))
        }

        let retained = tabIDs.filter {
            archive.archivedState(profileID: profileID, tabID: $0) != nil
        }
        XCTAssertEqual(retained, Array(tabIDs.suffix(3)))
    }

    func testRemovingAProfileLeavesEveryOtherProfileAlone() async throws {
        let archive = try makeArchive()
        let deleted = UUID()
        let kept = UUID()
        let deletedTab = TabID()
        let keptTab = TabID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))

        archive.archive(
            interactionState: Data("gone".utf8),
            url: url,
            profileID: deleted,
            tabID: deletedTab
        )
        archive.archive(
            interactionState: Data("stays".utf8),
            url: url,
            profileID: kept,
            tabID: keptTab
        )
        await archive.flushPendingWrites()

        archive.removeStates(profileID: deleted)
        await archive.flushPendingWrites()

        XCTAssertNil(archive.archivedState(profileID: deleted, tabID: deletedTab))
        XCTAssertNotNil(archive.archivedState(profileID: kept, tabID: keptTab))
    }

    func testPruningKeepsKnownTabsAndSkipsProfilesItWasNotToldAbout() async throws {
        let archive = try makeArchive()
        let swept = UUID()
        let untouched = UUID()
        let keptTab = TabID()
        let deletedTab = TabID()
        let otherProfileTab = TabID()
        let url = try XCTUnwrap(URL(string: "https://example.com/one"))

        for (profileID, tabID) in [
            (swept, keptTab),
            (swept, deletedTab),
            (untouched, otherProfileTab),
        ] {
            archive.archive(
                interactionState: Data("state".utf8),
                url: url,
                profileID: profileID,
                tabID: tabID
            )
        }
        await archive.flushPendingWrites()

        archive.pruneStates(keeping: [swept: [keptTab]])
        await archive.flushPendingWrites()

        XCTAssertNotNil(archive.archivedState(profileID: swept, tabID: keptTab))
        XCTAssertNil(archive.archivedState(profileID: swept, tabID: deletedTab))
        XCTAssertNotNil(
            archive.archivedState(profileID: untouched, tabID: otherProfileTab),
            "A sweep must not reach profiles outside the session it was given."
        )
    }

    private func makeArchive(
        maximumStateByteCount: Int = BrowserTabStateArchive.defaultMaximumStateByteCount,
        maximumStatesPerProfile: Int = BrowserTabStateArchive.defaultMaximumStatesPerProfile
    ) throws -> BrowserTabStateArchive {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("crest-tab-state-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return BrowserTabStateArchive(
            rootDirectory: root,
            maximumStateByteCount: maximumStateByteCount,
            maximumStatesPerProfile: maximumStatesPerProfile
        )
    }
}

/// The favicon side store the session core no longer carries bytes for.
final class BrowserFaviconFileStoreTests: XCTestCase {
    func testAnIconRoundTripsForItsOwnTab() async throws {
        let store = try makeStore()
        let tabID = TabID()
        let icon = Data("icon".utf8)

        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertEqual(store.favicon(tabID: tabID), icon)
        XCTAssertNil(store.favicon(tabID: TabID()))
    }

    func testIdenticalBytesAreNotRewritten() async throws {
        let store = try makeStore()
        let tabID = TabID()
        let icon = Data("steady".utf8)
        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()
        let firstIdentity = try fileIdentity(of: store.faviconFileURL(tabID: tabID))

        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertEqual(
            try fileIdentity(of: store.faviconFileURL(tabID: tabID)),
            firstIdentity,
            "An unchanged icon must not cost a write; an atomic write replaces the file."
        )

        store.reconcile(Data("changed".utf8), tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertNotEqual(
            try fileIdentity(of: store.faviconFileURL(tabID: tabID)),
            firstIdentity
        )
        XCTAssertEqual(store.favicon(tabID: tabID), Data("changed".utf8))
    }

    func testATabWithoutANewIconKeepsTheOneItHad() async throws {
        let store = try makeStore()
        let tabID = TabID()
        let icon = Data("cached".utf8)
        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()

        store.reconcile(nil, tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertEqual(store.favicon(tabID: tabID), icon)
    }

    func testAnOversizedIconIsIgnoredAndKeepsTheLastValidIcon() async throws {
        let store = try makeStore(maximumFaviconByteCount: 8)
        let tabID = TabID()
        let icon = Data("small".utf8)
        store.reconcile(icon, tabID: tabID)
        await store.flushPendingWrites()

        store.reconcile(Data(repeating: 7, count: 64), tabID: tabID)
        await store.flushPendingWrites()

        XCTAssertEqual(
            store.favicon(tabID: tabID),
            icon,
            "An invalid capture must not erase the last valid icon for a live tab."
        )
    }

    func testPruningKeepsOnlyTheTabsTheSessionStillHas() async throws {
        let store = try makeStore()
        let kept = TabID()
        let dropped = TabID()
        store.reconcile(Data("kept".utf8), tabID: kept)
        store.reconcile(Data("dropped".utf8), tabID: dropped)
        await store.flushPendingWrites()

        store.pruneFavicons(keeping: [kept])
        await store.flushPendingWrites()

        XCTAssertEqual(store.favicon(tabID: kept), Data("kept".utf8))
        XCTAssertNil(store.favicon(tabID: dropped))
    }

    private func fileIdentity(of url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.systemFileNumber] as? UInt64)
    }

    private func makeStore(
        maximumFaviconByteCount: Int = BrowserFaviconFileStore.defaultMaximumFaviconByteCount
    ) throws -> BrowserFaviconFileStore {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("crest-favicons-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return BrowserFaviconFileStore(
            rootDirectory: root,
            maximumFaviconByteCount: maximumFaviconByteCount
        )
    }
}
