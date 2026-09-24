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

    func testPinnedAndSavedTabsTrackWhenTheyLeaveTheirSavedLocation() throws {
        var pinned = BrowserTab(
            title: "Home",
            url: URL(string: "https://example.com/home#current"),
            savedURL: URL(string: "https://example.com/home#saved"),
            placement: .pinned
        )

        XCTAssertTrue(pinned.supportsSavedLocationEditing)
        XCTAssertFalse(
            pinned.isAwayFromSavedLocation,
            "Fragment-only navigation should still count as the saved page."
        )

        pinned.url = URL(string: "https://example.com/another-page")
        XCTAssertTrue(pinned.isAwayFromSavedLocation)

        let current = BrowserTab(
            title: "Current",
            url: try XCTUnwrap(URL(string: "https://example.com/current")),
            placement: .current
        )
        XCTAssertFalse(current.supportsSavedLocationEditing)
        XCTAssertFalse(current.isAwayFromSavedLocation)
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
        let now = Date(timeIntervalSince1970: 100_000)
        let store = makeStore(.cleanupFixture(now: now))
        let personalID = try XCTUnwrap(store.session.spaces.last?.id)

        XCTAssertTrue(store.sweepExpiredCurrentTabs(now: now))
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

        session = try BrowserCoreSync.repair(session)

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

    func testObservedPageTitleUpdatesNeverClobberARenamedTab() throws {
        let store = makeStore(.preview)
        let spaceID = store.selectedSpaceID
        let tabID = try XCTUnwrap(
            store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com/docs")))
        )
        XCTAssertTrue(store.setTabCustomTitle("Release Notes", for: tabID, in: spaceID))

        store.updateTabFromPage(
            committedURL: try XCTUnwrap(URL(string: "https://example.com/changelog")),
            title: "Changelog",
            for: tabID,
            matching: BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(store.selectedSpace))
        )

        let tab = try XCTUnwrap(store.selectedTab)
        XCTAssertEqual(tab.title, "Changelog")
        XCTAssertEqual(tab.customTitle, "Release Notes")
        XCTAssertEqual(tab.displayTitle, "Release Notes")
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
        let tabID = TabID(rawValue: try XCTUnwrap(UUID(uuidString: "F0000000-0000-0000-0000-000000000001")))
        let json = """
            {
              "id": {"rawValue": "\(tabID.rawValue.uuidString)"},
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

    func testABlankStoredCustomTitleFallsBackToThePageTitle() throws {
        let json = """
            {
              "id": {"rawValue": "F0000000-0000-0000-0000-000000000002"},
              "title": "Docs",
              "url": "https://example.com/docs",
              "symbol": "globe",
              "placement": "current",
              "lastActivatedAt": 100,
              "customTitle": "   "
            }
            """

        let decoded = try JSONDecoder().decode(
            BrowserTab.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(
            decoded.displayTitle,
            "Docs",
            "A blank name that arrived through storage or sync is not a rename."
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
        decoded = try BrowserCoreSync.repair(decoded)

        let tab = try XCTUnwrap(
            decoded.space(id: spaceID)?.tabs.first(where: { $0.id == renamed.id })
        )
        XCTAssertEqual(tab.customTitle, "Release Notes")
        XCTAssertEqual(tab.titleModifiedAt, renamedAt)
        XCTAssertEqual(tab.displayTitle, "Release Notes")
    }

    func testSpaceCapsPinnedGridAtTwelveTabs() throws {
        let store = makeStore(.preview)
        let limit = BrowserSpace.maximumPinnedTabs

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

        let session = try BrowserCoreSync.repair(BrowserSession(spaces: [first, second]))

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

        let session = try BrowserCoreSync.repair(BrowserSession(spaces: [emptySpace]))

        let repaired = try XCTUnwrap(session.space(id: emptySpace.id))
        XCTAssertEqual(repaired.tabs.count, 1)
        let launch = BrowserStoreSelection(launching: session)
        XCTAssertEqual(launch.selectedSpaceID, emptySpace.id)
        let launchTab = try XCTUnwrap(launch.selectedTab(in: session))
        XCTAssertEqual(launchTab.title, BrowserTab.startPageTitle)
        XCTAssertEqual(launchTab.symbol, BrowserTab.startPageSymbol)
        XCTAssertEqual(launchTab.placement, .current)

        let noSpaces = try BrowserCoreSync.repair(BrowserSession(spaces: []))
        XCTAssertEqual(noSpaces.spaces.count, 1)
        XCTAssertNotNil(BrowserStoreSelection(launching: noSpaces).selectedTab(in: noSpaces))
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

        let session = try BrowserCoreSync.repair(BrowserSession(spaces: [space]))

        let repaired = try XCTUnwrap(session.spaces.first)
        XCTAssertEqual(Set(repaired.folders.map(\.id)).count, 5)
        XCTAssertTrue(repaired.folderTree.isValid)
        XCTAssertTrue(
            repaired.folders.allSatisfy { folder in
                folder.parentID == nil || repaired.folders.contains { $0.id == folder.parentID }
            })
        XCTAssertEqual(repaired.pinnedTabs.count, BrowserSpace.maximumPinnedTabs)
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

    func testTwoBrowserWindowsKeepIndependentSpaceAndTabSelections() throws {
        let session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)
        let workTabID = try XCTUnwrap(work.tabs.first?.id)
        let personalTabID = try XCTUnwrap(personal.tabs.last?.id)
        var firstWindow = launchWindow(session)
        var secondWindow = launchWindow(session)

        firstWindow.selectTab(workTabID, in: work.id, session: session)
        secondWindow.selectTab(personalTabID, in: personal.id, session: session)

        XCTAssertEqual(firstWindow.selectedSpaceID, work.id)
        XCTAssertEqual(firstWindow.selectedTab(in: session)?.id, workTabID)
        XCTAssertEqual(secondWindow.selectedSpaceID, personal.id)
        XCTAssertEqual(secondWindow.selectedTab(in: session)?.id, personalTabID)
        XCTAssertNotEqual(firstWindow.id, secondWindow.id)
    }

    func testBrowserWindowSelectionRoundTripsForSceneRestoration() throws {
        let session = BrowserSession.preview
        let personal = try XCTUnwrap(session.spaces.last)
        let selectedTabID = try XCTUnwrap(personal.tabs.first?.id)
        var window = launchWindow(session)
        window.selectTab(selectedTabID, in: personal.id, session: session)

        let encoded = try JSONEncoder().encode(window)
        let restored = try JSONDecoder().decode(BrowserWindowState.self, from: encoded)

        XCTAssertEqual(restored, window)
        XCTAssertEqual(restored.selectedSpaceID, personal.id)
        XCTAssertEqual(restored.selectedTab(in: session)?.id, selectedTabID)
    }

    func testBrowserWindowChromeRoundTripsIndependentlyAndKeepsLegacySnapshotsReadable() throws {
        let session = BrowserSession.preview
        var firstWindow = launchWindow(session)
        var secondWindow = launchWindow(session)

        firstWindow.captureSidebar(width: 364, isPresented: false)
        secondWindow.captureSidebar(width: 278, isPresented: true)

        let firstRestored = try JSONDecoder().decode(
            BrowserWindowState.self,
            from: JSONEncoder().encode(firstWindow)
        )
        let secondRestored = try JSONDecoder().decode(
            BrowserWindowState.self,
            from: JSONEncoder().encode(secondWindow)
        )

        XCTAssertEqual(firstRestored.sidebarWidth, 364)
        XCTAssertEqual(firstRestored.sidebarIsPresented, false)
        XCTAssertEqual(secondRestored.sidebarWidth, 278)
        XCTAssertEqual(secondRestored.sidebarIsPresented, true)

        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(firstWindow)
            ) as? [String: Any]
        )
        legacyObject["sidebarWidth"] = nil
        legacyObject["sidebarIsPresented"] = nil
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacyRestored = try JSONDecoder().decode(
            BrowserWindowState.self,
            from: legacyData
        )

        XCTAssertNil(legacyRestored.sidebarWidth)
        XCTAssertNil(legacyRestored.sidebarIsPresented)
        XCTAssertEqual(legacyRestored.selectedSpaceID, firstWindow.selectedSpaceID)
    }

    func testBrowserWindowSelectionSnapshotIgnoresPageMetadataChanges() throws {
        var session = BrowserSession.preview
        let windowID = BrowserWindowID()
        let selection = BrowserStoreSelection(launching: session)
        let originalSelection = BrowserWindowState(id: windowID, restoring: selection, in: session)
        let spaceIndex = try XCTUnwrap(
            session.spaces.firstIndex { $0.id == selection.selectedSpaceID }
        )
        let selectedTabID = try XCTUnwrap(selection.selectedTabID(in: selection.selectedSpaceID))
        let tabIndex = try XCTUnwrap(
            session.spaces[spaceIndex].tabs.firstIndex { $0.id == selectedTabID }
        )

        session.spaces[spaceIndex].tabs[tabIndex].url = URL(string: "https://example.com/updated")
        session.spaces[spaceIndex].tabs[tabIndex].title = "Updated page title"

        XCTAssertEqual(
            BrowserWindowState(id: windowID, restoring: selection, in: session),
            originalSelection
        )
    }

    func testWindowPersistenceRestoresTwoWindowsAndRemovesOnlyTheClosedOne() async throws {
        let suiteName = "com.pauldavis.crest.tests.windows.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserWindowStatePersistence(defaults: defaults)
        let session = BrowserSession.preview
        let personal = try XCTUnwrap(session.spaces.last)
        let personalTabID = try XCTUnwrap(personal.tabs.last?.id)
        let firstWindow = launchWindow(session)
        var secondWindow = launchWindow(session)
        secondWindow.selectTab(personalTabID, in: personal.id, session: session)

        persistence.save(firstWindow)
        persistence.save(secondWindow)
        await persistence.flushPendingSaves()

        XCTAssertEqual(persistence.load(id: firstWindow.id), firstWindow)
        XCTAssertEqual(persistence.load(id: secondWindow.id), secondWindow)

        persistence.remove(id: firstWindow.id)
        await persistence.flushPendingSaves()

        XCTAssertNil(persistence.load(id: firstWindow.id))
        XCTAssertEqual(persistence.load(id: secondWindow.id), secondWindow)
    }

    // MARK: - Helpers

    /// A window store over `session` that opens the launch selection.
    private func makeStore(_ session: BrowserSession) -> BrowserStore {
        BrowserStore(session: session)
    }

    /// A new window record showing the launch selection of `session`.
    private func launchWindow(_ session: BrowserSession) -> BrowserWindowState {
        BrowserWindowState(restoring: BrowserStoreSelection(launching: session), in: session)
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

/// Records every `UserDefaults` write and removal a session save performs, so a
/// test can say which stores one mutation touched and how many bytes it cost.
final class BrowserSessionStorageWriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var writes: [(key: String, byteCount: Int)] = []
    private var removals: [String] = []

    var writtenKeys: [String] {
        lock.withLock { writes.map(\.key) }
    }

    var writtenByteCount: Int {
        lock.withLock { writes.reduce(0) { $0 + $1.byteCount } }
    }

    var removedKeys: [String] {
        lock.withLock { removals }
    }

    func byteCount(forKey key: String) -> Int {
        lock.withLock {
            writes.filter { $0.key == key }.reduce(0) { $0 + $1.byteCount }
        }
    }

    func reset() {
        lock.withLock {
            writes.removeAll()
            removals.removeAll()
        }
    }

    fileprivate func recordWrite(key: String, byteCount: Int) {
        lock.withLock { writes.append((key, byteCount)) }
    }

    fileprivate func recordRemoval(_ key: String) {
        lock.withLock { removals.append(key) }
    }

    var publisher: UserDefaultsBrowserSessionPersistence.Publisher {
        { [self] defaults, key, data in
            recordWrite(key: key, byteCount: data.count)
            defaults.set(data, forKey: key)
        }
    }

    var remover: UserDefaultsBrowserSessionPersistence.Remover {
        { [self] defaults, key in
            recordRemoval(key)
            defaults.removeObject(forKey: key)
        }
    }
}

/// An in-memory favicon store that also reports which tabs a save reconciled and
/// whether it swept, so a test can prove a save left icons alone.
final class SpyingBrowserFaviconStore: BrowserFaviconStoring, @unchecked Sendable {
    private let store = InMemoryBrowserFaviconStore()
    private let lock = NSLock()
    private var reconciled: [TabID] = []
    private var prunes: [Set<TabID>] = []

    var reconciledTabIDs: [TabID] {
        lock.withLock { reconciled }
    }

    var pruneRequests: [Set<TabID>] {
        lock.withLock { prunes }
    }

    var storedTabIDs: Set<TabID> {
        store.storedTabIDs
    }

    func reset() {
        lock.withLock {
            reconciled.removeAll()
            prunes.removeAll()
        }
    }

    func favicon(tabID: TabID) -> Data? {
        store.favicon(tabID: tabID)
    }

    func reconcile(_ faviconData: Data?, tabID: TabID) {
        lock.withLock { reconciled.append(tabID) }
        store.reconcile(faviconData, tabID: tabID)
    }

    func pruneFavicons(keeping tabIDs: Set<TabID>) {
        lock.withLock { prunes.append(tabIDs) }
        store.pruneFavicons(keeping: tabIDs)
    }
}

/// The split session store: a light core, one history key per Space, and a
/// favicon side store.
@MainActor
final class BrowserSessionStorageSplitTests: XCTestCase {
    private typealias Storage = UserDefaultsBrowserSessionPersistence

    private struct Harness {
        let defaults: UserDefaults
        let favicons: SpyingBrowserFaviconStore
        let recorder: BrowserSessionStorageWriteRecorder
        let persistence: UserDefaultsBrowserSessionPersistence
    }

    // MARK: - Stored layout

    func testASaveSplitsTheSessionAcrossTheCoreHistoryKeysAndTheFaviconStore() async throws {
        let session = try makeRichLegacySession()
        let harness = makeHarness()

        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()

        let coreData = try XCTUnwrap(harness.defaults.data(forKey: Storage.coreKey))
        let core = try JSONDecoder().decode(BrowserSession.self, from: coreData)
        XCTAssertTrue(
            core.spaces.allSatisfy(\.history.isEmpty),
            "The core must not carry history."
        )
        XCTAssertTrue(
            core.spaces.flatMap(\.tabs).allSatisfy { $0.faviconData == nil },
            "The core must not carry favicon bytes."
        )
        XCTAssertTrue(
            core.spaces.flatMap(\.archivedTabs).allSatisfy { $0.tab.faviconData == nil },
            "Closed tabs must not retain favicon bytes."
        )

        XCTAssertEqual(core.spaces.map(\.name), session.spaces.map(\.name))
        XCTAssertEqual(
            core.spaces.map { $0.folders.map(\.title) },
            session.spaces.map { $0.folders.map(\.title) }
        )
        XCTAssertEqual(
            core.spaces.flatMap { $0.tabs.map(\.customTitle) },
            session.spaces.flatMap { $0.tabs.map(\.customTitle) },
            "A renamed tab keeps its name in the core."
        )
        XCTAssertEqual(
            core.spaces.flatMap { $0.tabs.map(\.titleModifiedAt) },
            session.spaces.flatMap { $0.tabs.map(\.titleModifiedAt) }
        )
        XCTAssertEqual(
            core.spaces.flatMap { $0.tabs.map(\.faviconURL) },
            session.spaces.flatMap { $0.tabs.map(\.faviconURL) },
            "The core still frames each icon; only the bytes moved out."
        )

        for space in session.spaces {
            let data = try XCTUnwrap(
                harness.defaults.data(forKey: Storage.historyKey(for: space.id)),
                "Every Space with history needs its own key."
            )
            XCTAssertEqual(
                try JSONDecoder().decode([BrowserHistoryEntry].self, from: data),
                space.history
            )
        }

        for tab in session.spaces.flatMap({ $0.tabs + $0.archivedTabs.map(\.tab) })
        where tab.faviconData != nil {
            XCTAssertEqual(harness.favicons.favicon(tabID: tab.id), tab.faviconData)
        }

        XCTAssertNil(
            harness.defaults.data(forKey: Storage.legacyCoreKey),
            "Nothing may write the legacy whole-graph blob again."
        )
    }

    func testRelaunchingReproducesDisclosureStateAndLiveTabFavicons() async throws {
        var session = try makeRichLegacySession()
        for spaceIndex in session.spaces.indices {
            session.spaces[spaceIndex].isSavedTabsExpanded = false
            session.spaces[spaceIndex].savedTabsExpansionModifiedAt = Date(
                timeIntervalSince1970: 1_700_001_000 + Double(spaceIndex)
            )
        }
        let harness = makeHarness()
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()

        let relaunched = makeHarness(
            defaults: harness.defaults,
            favicons: harness.favicons
        )

        XCTAssertEqual(relaunched.persistence.load(), session)
    }

    func testNeitherStorePresentLoadsNothing() throws {
        XCTAssertNil(makeHarness().persistence.load())
    }

    // MARK: - Dirty tracking

    func testMissingFaviconCaptureKeepsTheLastSavedIconForALiveTab() async throws {
        var session = try makeRichLegacySession()
        let harness = makeHarness()
        let spaceID = session.spaces[0].id
        let tabID = session.spaces[0].tabs[0].id
        let icon = Self.faviconBytes(seed: 201, byteCount: 3_000)
        session.spaces[0].tabs[0].faviconData = icon
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()

        session.spaces[0].tabs[0].faviconData = nil
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()

        let relaunched = makeHarness(
            defaults: harness.defaults,
            favicons: harness.favicons
        )
        let restored = try XCTUnwrap(relaunched.persistence.load())
        let restoredTab = restored.space(id: spaceID)?.tabs.first { $0.id == tabID }

        XCTAssertEqual(restoredTab?.faviconData, icon)
    }

    // MARK: - Migration

    func testTheLegacyBlobMigratesIntoTheSplitLayoutAndIsLeftInPlace() async throws {
        let session = try makeRichLegacySession()
        let harness = makeHarness()
        let legacyData = try JSONEncoder().encode(session)
        harness.defaults.set(legacyData, forKey: Storage.legacyCoreKey)

        let migrated = try XCTUnwrap(harness.persistence.load())
        await harness.persistence.flushPendingSaves()

        XCTAssertEqual(
            migrated,
            session,
            "Migration hands back the legacy session unchanged, favicons and all."
        )
        XCTAssertNotNil(harness.defaults.data(forKey: Storage.coreKey))
        for space in session.spaces {
            XCTAssertNotNil(harness.defaults.data(forKey: Storage.historyKey(for: space.id)))
        }
        XCTAssertEqual(
            harness.defaults.data(forKey: Storage.legacyCoreKey),
            legacyData,
            "The legacy blob stays byte for byte, so a rollback still has a session."
        )
        XCTAssertTrue(harness.defaults.bool(forKey: Storage.legacyMigrationKey))

        let relaunched = makeHarness(defaults: harness.defaults, favicons: harness.favicons)
        XCTAssertEqual(
            relaunched.persistence.load(),
            session,
            "The next launch reads the split layout it just wrote."
        )
    }

    func testAPresentCoreWinsOverALegacyBlobAndNothingMigratesAgain() async throws {
        let session = try makeRichLegacySession()
        let harness = makeHarness()
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()

        var stale = session
        stale.spaces[0].tabs[0].title = "How this Space looked before the split"
        harness.defaults.set(try JSONEncoder().encode(stale), forKey: Storage.legacyCoreKey)

        let relaunched = makeHarness(defaults: harness.defaults, favicons: harness.favicons)
        let loaded = try XCTUnwrap(relaunched.persistence.load())

        XCTAssertEqual(loaded, session)
        XCTAssertFalse(
            harness.defaults.bool(forKey: Storage.legacyMigrationKey),
            "A session that was never migrated must not claim it was."
        )
    }

    func testAnUndecodableLegacyBlobIsAFreshInstallRatherThanACrash() throws {
        let harness = makeHarness()
        harness.defaults.set(Data("not a session".utf8), forKey: Storage.legacyCoreKey)

        XCTAssertNil(harness.persistence.load())
    }

    // MARK: - Measurement

    // MARK: - Helpers

    private func makeHarness(
        defaults: UserDefaults? = nil,
        favicons: SpyingBrowserFaviconStore? = nil
    ) -> Harness {
        let resolvedDefaults: UserDefaults
        if let defaults {
            resolvedDefaults = defaults
        } else {
            let suiteName = "BrowserSessionStorageSplitTests.\(UUID().uuidString)"
            // A suite of its own: the split writes several keys, and a test must
            // not read another test's Spaces.
            resolvedDefaults = UserDefaults(suiteName: suiteName) ?? .standard
            addTeardownBlock {
                resolvedDefaults.removePersistentDomain(forName: suiteName)
            }
        }
        let recorder = BrowserSessionStorageWriteRecorder()
        let faviconStore = favicons ?? SpyingBrowserFaviconStore()
        return Harness(
            defaults: resolvedDefaults,
            favicons: faviconStore,
            recorder: recorder,
            persistence: UserDefaultsBrowserSessionPersistence(
                defaults: resolvedDefaults,
                faviconStore: faviconStore,
                publisher: recorder.publisher,
                remover: recorder.remover
            )
        )
    }

    /// A session shaped like the whole-graph blob the split replaces: several
    /// Spaces with folders and pinned, saved, and current tabs; a renamed tab; an
    /// archived tab; favicons on live tabs; and history per Space.
    private func makeRichLegacySession(
        historyEntriesPerSpace: Int = 250,
        faviconByteCount: Int = 6 * 1_024
    ) throws -> BrowserSession {
        var session = BrowserSession.preview
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        for spaceIndex in session.spaces.indices {
            for tabIndex in session.spaces[spaceIndex].tabs.indices {
                guard let url = session.spaces[spaceIndex].tabs[tabIndex].url else { continue }
                session.spaces[spaceIndex].tabs[tabIndex].faviconData = Self.faviconBytes(
                    seed: UInt8(truncatingIfNeeded: spaceIndex * 31 + tabIndex),
                    byteCount: faviconByteCount
                )
                session.spaces[spaceIndex].tabs[tabIndex].faviconURL = url
                session.spaces[spaceIndex].tabs[tabIndex].iconAccent = BrowserTabIconAccent(
                    red: 0.1,
                    green: 0.5,
                    blue: 0.9
                )
            }
            let renamedTabIndex = try XCTUnwrap(
                session.spaces[spaceIndex].tabs.lastIndex { !$0.isStartPage }
            )
            session.spaces[spaceIndex].tabs[renamedTabIndex].customTitle =
                "Renamed in \(session.spaces[spaceIndex].name)"
            session.spaces[spaceIndex].tabs[renamedTabIndex].markTitleModified(at: epoch)
            let archivedTabID = try XCTUnwrap(
                session.spaces[spaceIndex].currentTabs.first { !$0.isStartPage }?.id
            )
            Self.archiveTab(archivedTabID, inSpaceAt: spaceIndex, of: &session, at: epoch)
            session.spaces[spaceIndex].history = (0..<historyEntriesPerSpace).map { index in
                BrowserHistoryEntry(
                    url: URL(
                        string: "https://example.com/space-\(spaceIndex)/page-\(index)"
                    )!,
                    title: "Space \(spaceIndex) page \(index)",
                    firstVisitedAt: epoch,
                    lastVisitedAt: epoch.addingTimeInterval(Double(index)),
                    visitCount: index % 7 + 1
                )
            }
        }
        XCTAssertFalse(session.spaces.flatMap(\.archivedTabs).isEmpty)
        return session
    }

    /// Closes a tab the way the core does: it leaves the live tabs for the
    /// archive and releases its cached favicon bytes.
    private static func archiveTab(
        _ tabID: TabID,
        inSpaceAt spaceIndex: Int,
        of session: inout BrowserSession,
        at date: Date
    ) {
        guard let tabIndex = session.spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = session.spaces[spaceIndex].tabs.remove(at: tabIndex)
        tab.faviconData = nil
        session.spaces[spaceIndex].archivedTabs.insert(
            ArchivedTab(tab: tab, archivedAt: date, reason: .closed),
            at: 0
        )
    }

    fileprivate static func faviconBytes(seed: UInt8, byteCount: Int) -> Data {
        Data((0..<byteCount).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
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
