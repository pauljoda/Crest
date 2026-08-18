import XCTest

@testable import Crest

final class BrowserSessionTests: XCTestCase {
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

    func testSavedLocationCanBeReplacedWithCurrentAndRestored() throws {
        let homeURL = try XCTUnwrap(URL(string: "https://example.com/home"))
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/current"))
        let laterURL = try XCTUnwrap(URL(string: "https://example.com/later"))
        let tab = BrowserTab(
            title: "Pinned",
            url: currentURL,
            savedURL: homeURL,
            placement: .pinned
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Editing",
            symbol: "pencil",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.replaceTabSavedLocationWithCurrent(
                tabID: tab.id,
                in: space.id
            )
        )
        XCTAssertEqual(session.selectedTab?.savedSiteURL, currentURL)
        XCTAssertFalse(try XCTUnwrap(session.selectedTab).isAwayFromSavedLocation)

        session.updateSelectedTab(url: laterURL, title: "Later")
        XCTAssertTrue(try XCTUnwrap(session.selectedTab).isAwayFromSavedLocation)

        XCTAssertEqual(
            session.restoreTabSavedLocation(tabID: tab.id, in: space.id),
            currentURL
        )
        XCTAssertEqual(session.selectedTab?.url, currentURL)
        XCTAssertFalse(try XCTUnwrap(session.selectedTab).isAwayFromSavedLocation)
    }

    func testPinnedTabDoubleClickRequestsItsSavedLocationOnlyWhenAway() throws {
        var tab = BrowserTab(
            title: "Media Library",
            url: try XCTUnwrap(URL(string: "https://media.example/audio/episode")),
            savedURL: try XCTUnwrap(URL(string: "https://media.example/")),
            placement: .pinned
        )

        XCTAssertTrue(BrowserPinnedTabInteraction.shouldRestoreSavedLocation(for: tab))

        tab.url = tab.savedURL
        XCTAssertFalse(BrowserPinnedTabInteraction.shouldRestoreSavedLocation(for: tab))
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

    func testOpeningATabAddsItOnlyToTheSelectedSpace() throws {
        var session = BrowserSession.preview
        let personalID = try XCTUnwrap(session.spaces.last?.id)
        let workCount = try XCTUnwrap(session.spaces.first?.currentTabs.count)
        let personalCount = try XCTUnwrap(session.spaces.last?.currentTabs.count)

        session.selectSpace(personalID)
        session.openTab(title: "A fresh tab", url: nil, at: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(session.space(id: personalID)?.currentTabs.count, personalCount + 1)
        XCTAssertEqual(session.spaces.first?.currentTabs.count, workCount)
    }

    func testExtensionCanOpenBackgroundTabWithoutChangingSpaceSelection() throws {
        var session = BrowserSession.preview
        let originalSpaceID = session.selectedSpaceID
        let originalTabID = session.selectedTab?.id
        let personal = try XCTUnwrap(session.spaces.last)

        let openedID = try XCTUnwrap(
            session.openTab(
                title: "Background",
                url: URL(string: "https://example.com/background"),
                in: personal.id,
                placement: .current,
                requestedIndex: personal.tabs.endIndex,
                shouldSelect: false
            )
        )

        XCTAssertEqual(session.selectedSpaceID, originalSpaceID)
        XCTAssertEqual(session.selectedTab?.id, originalTabID)
        XCTAssertTrue(session.space(id: personal.id)?.contains(openedID) == true)
    }

    func testExtensionCloseArchivesPinnedTabAndRepairsSelection() throws {
        var session = BrowserSession.preview
        let space = try XCTUnwrap(session.selectedSpace)
        let pinned = try XCTUnwrap(space.pinnedTabs.first)
        let fallbackID = try XCTUnwrap(
            space.tabs.first(where: { $0.id != pinned.id })?.id
        )
        XCTAssertTrue(session.activateTab(pinned.id, in: space.id))

        XCTAssertTrue(
            session.closeExtensionTab(
                pinned.id,
                in: space.id,
                fallbackTabID: fallbackID
            )
        )

        let updated = try XCTUnwrap(session.space(id: space.id))
        XCTAssertFalse(updated.contains(pinned.id))
        XCTAssertEqual(updated.archivedTabs.last?.id, pinned.id)
        XCTAssertEqual(updated.selectedTabID, fallbackID)
    }

    func testNewCurrentTabsUseArcsStableNewestFirstOrder() throws {
        var session = BrowserSession.preview

        let firstID = try XCTUnwrap(session.openTab(title: "First", url: nil))
        let secondID = try XCTUnwrap(session.openTab(title: "Second", url: nil))

        XCTAssertEqual(try XCTUnwrap(session.selectedSpace).currentTabs.prefix(2).map(\.id), [secondID, firstID])
        session.selectTab(firstID)
        XCTAssertEqual(try XCTUnwrap(session.selectedSpace).currentTabs.prefix(2).map(\.id), [secondID, firstID])
    }

    func testClosingASelectedCurrentTabReturnsToThePreviouslyActivatedTab() throws {
        var session = BrowserSession.preview
        let recent = Date(timeIntervalSince1970: 4_000_000_000)
        let previousID = try XCTUnwrap(
            session.openTab(
                title: "Previous",
                url: URL(string: "https://previous.example"),
                at: recent
            )
        )
        let selectedID = try XCTUnwrap(
            session.openTab(
                title: "Selected",
                url: URL(string: "https://selected.example"),
                at: recent.addingTimeInterval(10)
            )
        )
        _ = session.openTab(
            title: "Adjacent",
            url: URL(string: "https://adjacent.example"),
            at: recent.addingTimeInterval(20)
        )
        session.selectTab(previousID, at: recent.addingTimeInterval(100))
        session.selectTab(selectedID, at: recent.addingTimeInterval(110))

        session.closeTab(selectedID, fallbackTabID: previousID)

        XCTAssertEqual(session.selectedTab?.id, previousID)
    }

    func testClosingTheNewestCurrentTabLeavesTheUnloadedStateWithoutAFallback() throws {
        var session = BrowserSession.preview
        _ = try XCTUnwrap(session.openTab(title: "A", url: nil))
        let newestID = try XCTUnwrap(session.openTab(title: "B", url: nil))

        session.closeTab(newestID)

        XCTAssertNil(session.selectedTab)
    }

    func testTabDismissalClosesCurrentTabsButOnlyUnloadsPinnedAndSavedTabs() {
        let current = BrowserTab(
            title: "Current",
            url: URL(string: "https://current.example"),
            placement: .current
        )
        let pinned = BrowserTab(
            title: "Pinned",
            url: URL(string: "https://pinned.example"),
            placement: .pinned
        )
        let saved = BrowserTab(
            title: "Saved",
            url: URL(string: "https://saved.example"),
            placement: .saved
        )

        XCTAssertEqual(BrowserTabDismissalPolicy.action(for: current), .closeTab)
        XCTAssertEqual(BrowserTabDismissalPolicy.action(for: pinned), .unloadPage)
        XCTAssertEqual(BrowserTabDismissalPolicy.action(for: saved), .unloadPage)
        XCTAssertEqual(BrowserTabDismissalPolicy.action(for: .startPage()), .closeWindow)
        XCTAssertEqual(
            BrowserTabDismissalPolicy.action(for: .startPage(), tabCount: 2),
            .closeTab
        )
        XCTAssertEqual(BrowserTabDismissalPolicy.action(for: nil), .closeWindow)
    }

    func testSwitchingSpacesRestoresEachSpacesSelectedTab() throws {
        var session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)
        let workTabID = try XCTUnwrap(work.savedTabs.first?.id)
        let personalTabID = try XCTUnwrap(personal.pinnedTabs.last?.id)

        session.selectTab(workTabID)
        session.selectSpace(personal.id)
        session.selectTab(personalTabID)
        session.selectSpace(work.id)

        XCTAssertEqual(session.selectedTab?.id, workTabID)

        session.selectSpace(personal.id)
        XCTAssertEqual(session.selectedTab?.id, personalTabID)
    }

    func testRemovingTheSelectedFirstSpaceSelectsTheFollowingSpace() throws {
        var session = BrowserSession.preview
        let first = try XCTUnwrap(session.spaces.first)
        let following = try XCTUnwrap(session.spaces.dropFirst().first)
        session.selectSpace(first.id)

        let removed = session.removeSpace(first.id)

        XCTAssertEqual(removed, first)
        XCTAssertEqual(session.selectedSpaceID, following.id)
        XCTAssertEqual(session.selectedTab?.id, following.selectedTabID)
        XCTAssertNil(session.space(id: first.id))
    }

    func testRemovingTheSelectedLastSpaceSelectsThePreviousSpace() throws {
        var session = BrowserSession.preview
        let previous = try XCTUnwrap(session.spaces.dropLast().last)
        let last = try XCTUnwrap(session.spaces.last)
        session.selectSpace(last.id)

        let removed = session.removeSpace(last.id)

        XCTAssertEqual(removed, last)
        XCTAssertEqual(session.selectedSpaceID, previous.id)
        XCTAssertEqual(session.selectedTab?.id, previous.selectedTabID)
    }

    func testRemovingANonselectedSpacePreservesTheCurrentSelection() throws {
        var session = BrowserSession.preview
        let selected = try XCTUnwrap(session.spaces.first)
        let removedSpace = try XCTUnwrap(session.spaces.last)
        session.selectSpace(selected.id)

        XCTAssertEqual(session.removeSpace(removedSpace.id), removedSpace)
        XCTAssertEqual(session.selectedSpaceID, selected.id)
        XCTAssertEqual(session.selectedTab?.id, selected.selectedTabID)
    }

    func testRemovingTheOnlySpaceIsRefused() throws {
        var session = BrowserSession.preview
        session.spaces = [try XCTUnwrap(session.spaces.first)]
        session.selectedSpaceID = try XCTUnwrap(session.spaces.first?.id)

        XCTAssertNil(session.removeSpace(session.selectedSpaceID))
        XCTAssertEqual(session.spaces.count, 1)
    }

    func testEverySpaceHasAnIndependentWebsiteDataStore() {
        let session = BrowserSession.preview
        let profileIDs = Set(session.spaces.map(\.profile.id))

        XCTAssertEqual(profileIDs.count, session.spaces.count)
    }

    func testCleanupRemovesOnlyExpiredUnselectedCurrentTabs() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        var session = BrowserSession.cleanupFixture(now: now)
        let selectedID = try XCTUnwrap(session.selectedTab?.id)
        let pinnedIDs = Set(try XCTUnwrap(session.selectedSpace).pinnedTabs.map(\.id))
        let savedIDs = Set(try XCTUnwrap(session.selectedSpace).savedTabs.map(\.id))

        session.cleanupCurrentTabs(olderThan: 12 * 60 * 60, now: now)

        let selectedSpace = try XCTUnwrap(session.selectedSpace)
        XCTAssertEqual(selectedSpace.currentTabs.map(\.id), [selectedID])
        XCTAssertEqual(Set(selectedSpace.pinnedTabs.map(\.id)), pinnedIDs)
        XCTAssertEqual(Set(selectedSpace.savedTabs.map(\.id)), savedIDs)
        XCTAssertEqual(selectedSpace.archivedTabs.count, 2)
        XCTAssertTrue(selectedSpace.archivedTabs.allSatisfy { $0.reason == .autoCleanup })
        XCTAssertTrue(selectedSpace.archivedTabs.allSatisfy { $0.archivedAt == now })
    }

    func testClearingCurrentTabsArchivesCommittedTabsAndPreservesSavedContent() throws {
        let now = Date(timeIntervalSince1970: 300_000)
        let pinned = BrowserTab(
            title: "Pinned",
            url: try XCTUnwrap(URL(string: "https://example.test/pinned")),
            placement: .pinned
        )
        let saved = BrowserTab(
            title: "Saved",
            url: try XCTUnwrap(URL(string: "https://example.test/saved")),
            placement: .saved
        )
        let first = BrowserTab(
            title: "First",
            url: try XCTUnwrap(URL(string: "https://example.test/first")),
            placement: .current
        )
        let second = BrowserTab(
            title: "Second",
            url: try XCTUnwrap(URL(string: "https://example.test/second")),
            placement: .current
        )
        let draft = BrowserTab.startPage()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase",
            accent: .indigo,
            folders: [],
            tabs: [pinned, saved, first, second, draft],
            selectedTabID: second.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(session.clearCurrentTabs(in: space.id, at: now))

        let updated = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(updated.tabs.map(\.id), [pinned.id, saved.id])
        XCTAssertEqual(updated.selectedTabID, pinned.id)
        XCTAssertEqual(updated.archivedTabs.map(\.id), [first.id, second.id])
        XCTAssertTrue(updated.archivedTabs.allSatisfy { $0.reason == .closed })
        XCTAssertTrue(updated.archivedTabs.allSatisfy { $0.archivedAt == now })
        XCTAssertFalse(updated.archivedTabs.contains { $0.tab.isStartPage })
    }

    func testCleanupPolicyRemainsIndependentForEverySpace() throws {
        let now = Date(timeIntervalSince1970: 200_000)
        var session = BrowserSession.preview
        XCTAssertGreaterThanOrEqual(session.spaces.count, 2)
        let neverSpaceID = session.spaces[0].id
        let cleanupSpaceID = session.spaces[1].id
        let neverTab = BrowserTab(
            title: "Keep indefinitely",
            url: URL(string: "https://example.com/keep"),
            placement: .current,
            lastActivatedAt: now.addingTimeInterval(-31 * 24 * 60 * 60)
        )
        let cleanupTab = BrowserTab(
            title: "Archive by policy",
            url: URL(string: "https://example.com/archive"),
            placement: .current,
            lastActivatedAt: now.addingTimeInterval(-13 * 60 * 60)
        )
        session.spaces[0].tabs.append(neverTab)
        session.spaces[1].tabs.append(cleanupTab)
        session.spaces[0].browsingPreferences.currentTabCleanupPolicy = .never
        session.spaces[1].browsingPreferences.currentTabCleanupPolicy = .after12Hours

        session.cleanupCurrentTabsUsingSpacePreferences(now: now)

        XCTAssertTrue(try XCTUnwrap(session.space(id: neverSpaceID)).contains(neverTab.id))
        let cleanedSpace = try XCTUnwrap(session.space(id: cleanupSpaceID))
        XCTAssertFalse(cleanedSpace.contains(cleanupTab.id))
        XCTAssertEqual(
            cleanedSpace.archivedTabs.first(where: { $0.id == cleanupTab.id })?.reason,
            .autoCleanup
        )
    }

    func testRestoringAnArchivedTabReturnsItOnlyToItsSpaceAndSelectsIt() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        var session = BrowserSession.cleanupFixture(now: now)
        let personalID = try XCTUnwrap(session.spaces.last?.id)

        session.cleanupCurrentTabs(olderThan: 12 * 60 * 60, now: now)
        let archivedID = try XCTUnwrap(session.selectedSpace?.archivedTabs.first?.id)
        session.restoreArchivedTab(archivedID, at: now.addingTimeInterval(60))

        XCTAssertEqual(session.selectedTab?.id, archivedID)
        XCTAssertEqual(session.selectedTab?.placement, .current)
        XCTAssertEqual(try XCTUnwrap(session.selectedSpace).currentTabs.first?.id, archivedID)
        XCTAssertFalse(try XCTUnwrap(session.selectedSpace).archivedTabs.contains { $0.id == archivedID })
        XCTAssertEqual(try XCTUnwrap(session.selectedSpace).archivedTabs.count, 1)
        XCTAssertTrue(try XCTUnwrap(session.space(id: personalID)).archivedTabs.isEmpty)
    }

    func testClosingACurrentTabArchivesItForRecovery() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        var session = BrowserSession.preview
        let tabID = try XCTUnwrap(session.openTab(title: "Temporary", url: URL(string: "https://example.com"), at: now))

        session.closeTab(tabID, at: now.addingTimeInterval(30))

        let archived = try XCTUnwrap(session.selectedSpace?.archivedTabs.first(where: { $0.id == tabID }))
        XCTAssertEqual(archived.reason, .closed)
        XCTAssertEqual(archived.archivedAt, now.addingTimeInterval(30))
        XCTAssertFalse(try XCTUnwrap(session.selectedSpace).contains(tabID))
    }

    func testClosingAStartPageDraftNeverAddsItToTheArchive() throws {
        var session = BrowserSession.preview
        let startPage = try XCTUnwrap(
            session.selectedSpace?.currentTabs.first(where: \.isStartPage)
        )
        let archivedIDsBeforeClosing = try XCTUnwrap(session.selectedSpace)
            .archivedTabs
            .map(\.id)

        session.closeTab(startPage.id)

        let updatedSpace = try XCTUnwrap(session.selectedSpace)
        XCTAssertFalse(updatedSpace.contains(startPage.id))
        XCTAssertEqual(updatedSpace.archivedTabs.map(\.id), archivedIDsBeforeClosing)
        XCTAssertFalse(updatedSpace.archivedTabs.contains { $0.tab.isStartPage })
    }

    func testRuntimeRepairDropsLegacyStartPageDraftsFromTheArchive() throws {
        var session = BrowserSession.preview
        let spaceIndex = try XCTUnwrap(
            session.spaces.firstIndex(where: { $0.id == session.selectedSpaceID })
        )
        session.spaces[spaceIndex].archivedTabs = [
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

        session.repairRuntimeIntegrity()

        let archive = try XCTUnwrap(session.selectedSpace).archivedTabs
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
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        session.openTab(title: "Docs", url: URL(string: "https://example.com/docs"))
        let tabID = try XCTUnwrap(session.selectedTab?.id)
        let renamedAt = Date(timeIntervalSince1970: 4_000)

        XCTAssertTrue(
            session.setTabCustomTitle(
                "  Release Notes  ",
                tabID: tabID,
                in: spaceID,
                at: renamedAt
            )
        )

        let renamed = try XCTUnwrap(session.selectedTab)
        XCTAssertEqual(renamed.customTitle, "Release Notes")
        XCTAssertEqual(renamed.displayTitle, "Release Notes")
        XCTAssertEqual(
            renamed.title,
            "Docs",
            "A rename layers over the page title instead of replacing it."
        )
        XCTAssertEqual(renamed.titleModifiedAt, renamedAt)

        XCTAssertFalse(
            session.setTabCustomTitle(
                "Release Notes",
                tabID: tabID,
                in: spaceID,
                at: renamedAt.addingTimeInterval(60)
            ),
            "Re-committing the same name is not a change."
        )

        XCTAssertTrue(
            session.setTabCustomTitle(
                "",
                tabID: tabID,
                in: spaceID,
                at: renamedAt.addingTimeInterval(120)
            )
        )
        let cleared = try XCTUnwrap(session.selectedTab)
        XCTAssertNil(cleared.customTitle)
        XCTAssertEqual(cleared.displayTitle, "Docs")
        XCTAssertEqual(cleared.titleModifiedAt, renamedAt.addingTimeInterval(120))
    }

    func testKeepLoadedCanBeEnabledAndRemovedWithoutChangingTheTabPlacement() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let tabID = try XCTUnwrap(session.selectedTab?.id)
        let placement = try XCTUnwrap(session.selectedTab?.placement)

        XCTAssertTrue(
            session.setTabKeepsPageLoaded(
                true,
                tabID: tabID,
                in: spaceID
            )
        )
        XCTAssertEqual(session.selectedTab?.keepsPageLoaded, true)
        XCTAssertEqual(session.selectedTab?.placement, placement)
        XCTAssertFalse(
            session.setTabKeepsPageLoaded(
                true,
                tabID: tabID,
                in: spaceID
            )
        )
        XCTAssertTrue(
            session.setTabKeepsPageLoaded(
                false,
                tabID: tabID,
                in: spaceID
            )
        )
        XCTAssertEqual(session.selectedTab?.keepsPageLoaded, false)
        XCTAssertEqual(session.selectedTab?.placement, placement)
    }

    func testObservedPageTitleUpdatesNeverClobberARenamedTab() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        session.openTab(title: "Docs", url: URL(string: "https://example.com/docs"))
        let tabID = try XCTUnwrap(session.selectedTab?.id)
        XCTAssertTrue(
            session.setTabCustomTitle("Release Notes", tabID: tabID, in: spaceID)
        )

        session.updateSelectedTab(
            url: URL(string: "https://example.com/changelog"),
            title: "Changelog"
        )

        let tab = try XCTUnwrap(session.selectedTab)
        XCTAssertEqual(tab.title, "Changelog")
        XCTAssertEqual(tab.customTitle, "Release Notes")
        XCTAssertEqual(tab.displayTitle, "Release Notes")
    }

    func testRenamingATabDoesNotClaimANewerPositionChange() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let tabID = try XCTUnwrap(session.selectedTab?.id)
        let movedAt = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(session.moveTab(tabID, to: .pinned, at: movedAt))

        XCTAssertTrue(
            session.setTabCustomTitle(
                "Inbox",
                tabID: tabID,
                in: spaceID,
                at: movedAt.addingTimeInterval(100)
            )
        )

        XCTAssertEqual(session.selectedTab?.positionModifiedAt, movedAt)
        XCTAssertEqual(
            session.selectedTab?.titleModifiedAt,
            movedAt.addingTimeInterval(100)
        )
    }

    func testDuplicatingARenamedTabCarriesTheRename() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        session.openTab(title: "Docs", url: URL(string: "https://example.com/docs"))
        let tabID = try XCTUnwrap(session.selectedTab?.id)
        XCTAssertTrue(
            session.setTabCustomTitle("Release Notes", tabID: tabID, in: spaceID)
        )

        let duplicateID = try XCTUnwrap(session.duplicateTab(tabID, in: spaceID))

        let duplicate = try XCTUnwrap(
            session.selectedSpace?.tabs.first(where: { $0.id == duplicateID })
        )
        XCTAssertEqual(duplicate.customTitle, "Release Notes")
        XCTAssertEqual(duplicate.displayTitle, "Release Notes")
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
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        session.openTab(title: "Docs", url: URL(string: "https://example.com/docs"))
        let tabID = try XCTUnwrap(session.selectedTab?.id)
        let renamedAt = Date(timeIntervalSince1970: 4_000)
        XCTAssertTrue(
            session.setTabCustomTitle(
                "Release Notes",
                tabID: tabID,
                in: spaceID,
                at: renamedAt
            )
        )

        var decoded = try JSONDecoder().decode(
            BrowserSession.self,
            from: try JSONEncoder().encode(session)
        )
        decoded.repairRuntimeIntegrity()

        let tab = try XCTUnwrap(
            decoded.space(id: spaceID)?.tabs.first(where: { $0.id == tabID })
        )
        XCTAssertEqual(tab.customTitle, "Release Notes")
        XCTAssertEqual(tab.titleModifiedAt, renamedAt)
        XCTAssertEqual(tab.displayTitle, "Release Notes")
    }

    func testSpaceCapsPinnedGridAtTwelveTabs() throws {
        var session = BrowserSession.preview

        for index in 0..<8 {
            session.openTab(title: "Pinned \(index)", url: nil)
            session.moveSelectedTab(to: .pinned)
        }

        session.openTab(title: "Thirteenth pin", url: nil)
        let overflowID = try XCTUnwrap(session.selectedTab?.id)
        session.moveSelectedTab(to: .pinned)

        let space = try XCTUnwrap(session.selectedSpace)
        XCTAssertEqual(space.pinnedTabs.count, BrowserSpace.maximumPinnedTabs)
        XCTAssertEqual(space.tabs.first(where: { $0.id == overflowID })?.placement, .current)
    }

    func testTabMoveReordersWithinASectionWithoutChangingSelection() throws {
        var session = BrowserSession.preview
        session.openTab(title: "Older", url: nil)
        let olderID = try XCTUnwrap(session.selectedTab?.id)
        session.openTab(title: "Newest", url: nil)
        let newestID = try XCTUnwrap(session.selectedTab?.id)
        let movedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(
            session.moveTab(
                olderID,
                to: .current,
                before: newestID,
                at: movedAt
            )
        )

        XCTAssertEqual(
            Array(try XCTUnwrap(session.selectedSpace).currentTabs.prefix(2)).map(\.id), [olderID, newestID])
        XCTAssertEqual(session.selectedTab?.id, newestID)
        XCTAssertEqual(
            session.selectedSpace?.tabs.first(where: { $0.id == olderID })?.positionModifiedAt,
            movedAt
        )
    }

    func testTabActivationDoesNotClaimANewerPositionChange() throws {
        var session = BrowserSession.preview
        let tabID = try XCTUnwrap(session.selectedTab?.id)
        let positionModifiedAt = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(
            session.moveTab(
                tabID,
                to: .pinned,
                at: positionModifiedAt
            )
        )

        session.selectTab(tabID, at: positionModifiedAt.addingTimeInterval(100))

        XCTAssertEqual(session.selectedTab?.positionModifiedAt, positionModifiedAt)
    }

    func testTabMoveChangesDurabilityAndFolderWithoutChangingIdentity() throws {
        var session = BrowserSession.preview
        session.openTab(title: "Movable", url: URL(string: "https://example.com"))
        let tabID = try XCTUnwrap(session.selectedTab?.id)
        let folderID = try XCTUnwrap(session.selectedSpace?.folders.first?.id)

        XCTAssertTrue(session.moveTab(tabID, to: .saved, folderID: folderID))
        XCTAssertEqual(session.selectedTab?.id, tabID)
        XCTAssertEqual(session.selectedTab?.placement, .saved)
        XCTAssertEqual(session.selectedTab?.folderID, folderID)

        XCTAssertTrue(session.moveTab(tabID, to: .pinned))
        XCTAssertEqual(session.selectedTab?.id, tabID)
        XCTAssertEqual(session.selectedTab?.placement, .pinned)
        XCTAssertNil(session.selectedTab?.folderID)

        XCTAssertTrue(session.moveTab(tabID, to: .current))
        XCTAssertEqual(session.selectedTab?.id, tabID)
        XCTAssertEqual(session.selectedTab?.placement, .current)
    }

    func testCrossSpaceMovePreservesTabIdentityButReownsItAndSelectsTheDestination() throws {
        var session = BrowserSession.preview
        let sourceSpace = try XCTUnwrap(session.spaces.first)
        let destinationSpace = try XCTUnwrap(session.spaces.last)
        let movedTab = try XCTUnwrap(sourceSpace.savedTabs.first)
        let sourceFallbackID = sourceSpace.currentTabs.first?.id
        session.selectTab(movedTab.id, at: Date(timeIntervalSince1970: 900))

        XCTAssertTrue(
            session.moveTab(
                movedTab.id,
                from: sourceSpace.id,
                into: destinationSpace.id,
                at: Date(timeIntervalSince1970: 1_000)
            )
        )

        XCTAssertFalse(try XCTUnwrap(session.space(id: sourceSpace.id)).contains(movedTab.id))
        let destination = try XCTUnwrap(session.space(id: destinationSpace.id))
        let reownedTab = try XCTUnwrap(destination.tabs.first(where: { $0.id == movedTab.id }))
        XCTAssertEqual(reownedTab.url, movedTab.url)
        XCTAssertEqual(reownedTab.savedURL, movedTab.savedURL)
        XCTAssertEqual(reownedTab.placement, .saved)
        XCTAssertNil(reownedTab.folderID)
        XCTAssertEqual(reownedTab.lastActivatedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(session.selectedSpaceID, destinationSpace.id)
        XCTAssertEqual(destination.selectedTabID, movedTab.id)
        XCTAssertEqual(session.space(id: sourceSpace.id)?.selectedTabID, sourceFallbackID)

        let assignment = try XCTUnwrap(
            session.tabRuntimeAssignments.first(where: { $0.tabID == movedTab.id })
        )
        XCTAssertEqual(assignment.spaceID, destinationSpace.id)
        XCTAssertEqual(assignment.profileID, destinationSpace.profile.id)
    }

    func testCrossSpaceMoveCanChooseDestinationFolderAndDurability() throws {
        var session = BrowserSession.preview
        let source = try XCTUnwrap(session.spaces.first)
        let destination = try XCTUnwrap(session.spaces.last)
        let destinationFolderID = try XCTUnwrap(destination.folders.first?.id)
        let movedTab = try XCTUnwrap(source.currentTabs.first)

        XCTAssertTrue(
            session.moveTab(
                movedTab.id,
                from: source.id,
                into: destination.id,
                to: .saved,
                folderID: destinationFolderID
            )
        )

        let result = try XCTUnwrap(
            session.space(id: destination.id)?.tabs.first(where: { $0.id == movedTab.id })
        )
        XCTAssertEqual(result.placement, .saved)
        XCTAssertEqual(result.folderID, destinationFolderID)
        XCTAssertEqual(result.savedURL, movedTab.url)
    }

    func testCrossSpaceMoveRefusesAThirteenthDestinationPinWithoutMutatingEitherSpace() throws {
        var session = BrowserSession.preview
        let source = try XCTUnwrap(session.spaces.first)
        let destinationID = try XCTUnwrap(session.spaces.last?.id)
        let sourcePinnedTab = try XCTUnwrap(source.pinnedTabs.first)
        let destinationIndex = try XCTUnwrap(
            session.spaces.firstIndex(where: { $0.id == destinationID })
        )
        while session.spaces[destinationIndex].pinnedTabs.count < BrowserSpace.maximumPinnedTabs {
            session.spaces[destinationIndex].tabs.insert(
                BrowserTab(title: "Full pin", url: nil, placement: .pinned),
                at: 0
            )
        }
        let original = session

        XCTAssertFalse(
            session.moveTab(
                sourcePinnedTab.id,
                from: source.id,
                into: destinationID
            )
        )
        XCTAssertEqual(session, original)
    }

    func testDuplicatingAnyTabCreatesANewCurrentTabWithoutCopyingDurability() throws {
        var session = BrowserSession.preview
        let space = try XCTUnwrap(session.spaces.first)
        let source = try XCTUnwrap(space.savedTabs.first)

        let duplicateID = try XCTUnwrap(
            session.duplicateTab(
                source.id,
                in: space.id,
                at: Date(timeIntervalSince1970: 2_000)
            )
        )

        let duplicate = try XCTUnwrap(
            session.space(id: space.id)?.tabs.first(where: { $0.id == duplicateID })
        )
        XCTAssertNotEqual(duplicate.id, source.id)
        XCTAssertEqual(duplicate.title, source.title)
        XCTAssertEqual(duplicate.url, source.url)
        XCTAssertEqual(duplicate.faviconData, source.faviconData)
        XCTAssertEqual(duplicate.placement, .current)
        XCTAssertNil(duplicate.savedURL)
        XCTAssertNil(duplicate.folderID)
        XCTAssertEqual(session.selectedTab?.id, duplicateID)
    }

    func testDeletingPinnedAndSavedTabsLeavesExplicitArchiveEvidence() throws {
        var session = BrowserSession.preview
        let space = try XCTUnwrap(session.selectedSpace)
        let pinned = try XCTUnwrap(space.pinnedTabs.first)
        let saved = try XCTUnwrap(space.savedTabs.first)
        let archivedIDs = Set(space.archivedTabs.map(\.id))
        let deletedAt = Date(timeIntervalSince1970: 2_000)

        XCTAssertTrue(session.deleteTab(pinned.id, in: space.id, at: deletedAt))
        XCTAssertTrue(session.deleteTab(saved.id, in: space.id, at: deletedAt))

        let updated = try XCTUnwrap(session.space(id: space.id))
        XCTAssertFalse(updated.contains(pinned.id))
        XCTAssertFalse(updated.contains(saved.id))
        let deletionEvidence = updated.archivedTabs.filter {
            $0.id == pinned.id || $0.id == saved.id
        }
        XCTAssertEqual(Set(updated.archivedTabs.map(\.id)), archivedIDs.union([pinned.id, saved.id]))
        XCTAssertEqual(deletionEvidence.map(\.reason), [.deleted, .deleted])
        XCTAssertTrue(deletionEvidence.allSatisfy { $0.archivedAt == deletedAt })
        XCTAssertNotNil(updated.selectedTabID)
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

    func testAutomaticFaviconCacheKeepsLastKnownGoodIconWhileCurrentURLChanges() throws {
        var session = BrowserSession.preview
        let tab = try XCTUnwrap(
            session.selectedSpace?.currentTabs.first { $0.url != nil }
        )
        session.selectTab(tab.id)
        let originalURL = try XCTUnwrap(tab.url)
        let nextURL = try XCTUnwrap(URL(string: "https://example.com/next"))

        XCTAssertTrue(
            session.cacheAutomaticTabFavicon(
                Data([0x01]),
                iconAccent: .white,
                url: originalURL,
                tabID: tab.id,
                in: session.selectedSpaceID
            )
        )
        session.updateSelectedTab(url: nextURL, title: "Next")

        XCTAssertEqual(session.selectedTab?.iconMode, .automatic)
        XCTAssertEqual(session.selectedTab?.faviconData, Data([0x01]))
        XCTAssertEqual(session.selectedTab?.faviconURL, originalURL)
        XCTAssertEqual(session.selectedTab?.displayFaviconData, Data([0x01]))
        XCTAssertFalse(try XCTUnwrap(session.selectedTab).hasCurrentAutomaticFavicon)
    }

    func testAutomaticFaviconCacheReplacesLastKnownGoodIconAfterCapture() throws {
        var session = BrowserSession.preview
        let tab = try XCTUnwrap(
            session.selectedSpace?.currentTabs.first { $0.url != nil }
        )
        session.selectTab(tab.id)
        let originalURL = try XCTUnwrap(tab.url)
        let nextURL = try XCTUnwrap(URL(string: "https://example.com/next"))

        XCTAssertTrue(
            session.cacheAutomaticTabFavicon(
                Data([0x01]),
                iconAccent: .white,
                url: originalURL,
                tabID: tab.id,
                in: session.selectedSpaceID
            )
        )
        session.updateSelectedTab(url: nextURL, title: "Next")
        XCTAssertTrue(
            session.cacheAutomaticTabFavicon(
                Data([0x02]),
                iconAccent: .white,
                url: nextURL,
                tabID: tab.id,
                in: session.selectedSpaceID
            )
        )

        XCTAssertEqual(session.selectedTab?.displayFaviconData, Data([0x02]))
        XCTAssertEqual(session.selectedTab?.faviconURL, nextURL)
        XCTAssertTrue(try XCTUnwrap(session.selectedTab).hasCurrentAutomaticFavicon)
    }

    func testPulledFaviconRemainsAnOverrideAcrossNavigation() throws {
        var session = BrowserSession.preview
        let tab = try XCTUnwrap(session.selectedTab)
        let favicon = Data([0x01, 0x02, 0x03])

        XCTAssertTrue(
            session.setTabFavicon(
                favicon,
                iconAccent: .white,
                tabID: tab.id,
                in: session.selectedSpaceID
            )
        )
        session.updateSelectedTab(
            url: try XCTUnwrap(URL(string: "https://example.com/next")),
            title: "Next",
            faviconData: Data([0x04])
        )

        XCTAssertEqual(session.selectedTab?.iconMode, .pulled)
        XCTAssertEqual(session.selectedTab?.faviconData, favicon)
    }

    func testEmojiIconReplacesCachedFaviconAndRoundTrips() throws {
        var session = BrowserSession.preview
        let tab = try XCTUnwrap(session.selectedTab)
        let favicon = Data([0x01, 0x02, 0x03])

        XCTAssertTrue(
            session.setTabFavicon(
                favicon,
                iconAccent: .white,
                tabID: tab.id,
                in: session.selectedSpaceID
            )
        )
        XCTAssertTrue(
            session.setTabEmojiIcon(
                "🌐",
                tabID: tab.id,
                in: session.selectedSpaceID
            )
        )
        let updated = try XCTUnwrap(session.selectedTab)

        XCTAssertEqual(updated.iconMode, .emoji)
        XCTAssertEqual(updated.emojiIcon, "🌐")
        XCTAssertNil(updated.faviconData)
        XCTAssertNil(updated.faviconURL)

        let decoded = try JSONDecoder().decode(
            BrowserTab.self,
            from: JSONEncoder().encode(updated)
        )
        XCTAssertEqual(decoded.iconMode, .emoji)
        XCTAssertEqual(decoded.emojiIcon, "🌐")
        XCTAssertNil(decoded.faviconData)
    }

    func testClearingAnIconReturnsTheTabToAutomaticCurrentURLUpdates() throws {
        var session = BrowserSession.preview
        let tab = try XCTUnwrap(session.selectedTab)
        XCTAssertTrue(
            session.setTabEmojiIcon(
                "✨",
                tabID: tab.id,
                in: session.selectedSpaceID
            )
        )

        XCTAssertTrue(
            session.clearTabIcon(tabID: tab.id, in: session.selectedSpaceID)
        )

        XCTAssertEqual(session.selectedTab?.iconMode, .automatic)
        XCTAssertEqual(session.selectedTab?.symbol, "globe")
        XCTAssertNil(session.selectedTab?.faviconData)
    }

    func testFolderTreePreservesPreorderPathsAndAncestorDisclosure() throws {
        let root = SavedFolder(title: "Projects")
        let child = SavedFolder(title: "Crest", parentID: root.id)
        let grandchild = SavedFolder(title: "Research", parentID: child.id)
        let sibling = SavedFolder(title: "Travel")
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

    func testFolderLifecycleCreatesRenamesMovesAndRejectsCycles() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let rootID = try XCTUnwrap(session.addFolder(title: "Projects", in: spaceID))
        let childID = try XCTUnwrap(
            session.addFolder(title: "Crest", parentID: rootID, in: spaceID)
        )
        let leafID = try XCTUnwrap(
            session.addFolder(title: "Research", parentID: childID, in: spaceID)
        )

        XCTAssertTrue(session.renameFolder(childID, in: spaceID, title: "Browser"))
        XCTAssertFalse(session.canMoveFolder(rootID, in: spaceID, into: leafID))
        XCTAssertFalse(session.moveFolder(rootID, in: spaceID, into: leafID))
        XCTAssertTrue(session.moveFolder(childID, in: spaceID, into: nil))

        let space = try XCTUnwrap(session.space(id: spaceID))
        XCTAssertEqual(space.folders.first(where: { $0.id == childID })?.title, "Browser")
        XCTAssertNil(space.folders.first(where: { $0.id == childID })?.parentID)
        XCTAssertEqual(space.folders.first(where: { $0.id == leafID })?.parentID, childID)
        XCTAssertTrue(space.folderTree.isValid)
    }

    func testFoldersUseMutedDefaultColorAndPersistCustomColor() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let folderID = try XCTUnwrap(session.addFolder(in: spaceID))

        XCTAssertEqual(
            session.space(id: spaceID)?.folders.first(where: { $0.id == folderID })?.color,
            .folderDefault
        )

        let custom = BrowserSpaceBrandColor(
            red: 0.19,
            green: 0.43,
            blue: 0.71
        )
        XCTAssertTrue(session.setFolderColor(folderID, in: spaceID, color: custom))
        XCTAssertEqual(
            session.space(id: spaceID)?.folders.first(where: { $0.id == folderID })?.color,
            custom
        )
    }

    func testFolderCollapseStateChangesOnlyWhenNeeded() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let folderID = try XCTUnwrap(session.addFolder(in: spaceID))
        let collapseDate = Date(timeIntervalSince1970: 100)
        let expandDate = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(
            session.setFolderCollapsed(
                folderID,
                in: spaceID,
                isCollapsed: true,
                at: collapseDate
            )
        )
        let collapsed = session.space(id: spaceID)?.folders.first { $0.id == folderID }
        XCTAssertEqual(collapsed?.isCollapsed, true)
        XCTAssertEqual(collapsed?.collapseModifiedAt, collapseDate)
        XCTAssertFalse(
            session.setFolderCollapsed(
                folderID,
                in: spaceID,
                isCollapsed: true,
                at: expandDate
            )
        )
        XCTAssertTrue(
            session.setFolderCollapsed(
                folderID,
                in: spaceID,
                isCollapsed: false,
                at: expandDate
            )
        )
        let expanded = session.space(id: spaceID)?.folders.first { $0.id == folderID }
        XCTAssertEqual(expanded?.isCollapsed, false)
        XCTAssertEqual(expanded?.collapseModifiedAt, expandDate)
    }

    func testSavedTabsExpansionStateChangesOnlyWhenNeeded() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let collapseDate = Date(timeIntervalSince1970: 300)
        let expandDate = Date(timeIntervalSince1970: 400)

        XCTAssertTrue(
            session.setSavedTabsExpanded(false, in: spaceID, at: collapseDate)
        )
        XCTAssertEqual(session.space(id: spaceID)?.isSavedTabsExpanded, false)
        XCTAssertEqual(
            session.space(id: spaceID)?.savedTabsExpansionModifiedAt,
            collapseDate
        )
        XCTAssertFalse(
            session.setSavedTabsExpanded(false, in: spaceID, at: expandDate)
        )
        XCTAssertTrue(
            session.setSavedTabsExpanded(true, in: spaceID, at: expandDate)
        )
        XCTAssertEqual(session.space(id: spaceID)?.isSavedTabsExpanded, true)
        XCTAssertEqual(
            session.space(id: spaceID)?.savedTabsExpansionModifiedAt,
            expandDate
        )
    }

    func testDeletingFolderPromotesDirectChildrenAndKeepsTabsSaved() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let parentID = try XCTUnwrap(session.addFolder(title: "Parent", in: spaceID))
        let deletedID = try XCTUnwrap(
            session.addFolder(title: "Delete", parentID: parentID, in: spaceID)
        )
        let childID = try XCTUnwrap(
            session.addFolder(title: "Child", parentID: deletedID, in: spaceID)
        )
        let tabID = try XCTUnwrap(session.openTab(title: "Saved", url: URL(string: "https://example.com")))
        XCTAssertTrue(session.moveTab(tabID, to: .saved, folderID: deletedID))

        XCTAssertTrue(session.deleteFolder(deletedID, in: spaceID))

        let space = try XCTUnwrap(session.space(id: spaceID))
        XCTAssertFalse(space.folders.contains { $0.id == deletedID })
        XCTAssertEqual(space.folders.first(where: { $0.id == childID })?.parentID, parentID)
        XCTAssertEqual(space.tabs.first(where: { $0.id == tabID })?.folderID, parentID)
        XCTAssertEqual(space.tabs.first(where: { $0.id == tabID })?.placement, .saved)
    }

    func testFolderDepthIsBoundedForCreationAndMovement() throws {
        var session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        var parentID: FolderID?
        for depth in 0..<BrowserSpace.maximumFolderDepth {
            parentID = try XCTUnwrap(
                session.addFolder(
                    title: "Level \(depth)",
                    parentID: parentID,
                    in: spaceID
                )
            )
        }

        XCTAssertNil(
            session.addFolder(title: "Too Deep", parentID: parentID, in: spaceID)
        )
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: spaceID)).folderTree.depth(
                of: try XCTUnwrap(parentID)
            ),
            BrowserSpace.maximumFolderDepth - 1
        )
    }

    func testLegacyFolderWithoutParentDecodesAsTopLevel() throws {
        let source = SavedFolder(title: "Legacy")
        let encoded = try JSONEncoder().encode(source)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "parentID")
        object.removeValue(forKey: "color")
        object.removeValue(forKey: "isCollapsed")
        object.removeValue(forKey: "collapseModifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SavedFolder.self, from: legacyData)

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
            tabs: [firstTab],
            selectedTabID: sharedTabID
        )
        let second = BrowserSpace(
            id: SpaceID(),
            profile: sharedProfile,
            name: "Personal",
            symbol: "house",
            accent: .orange,
            folders: [],
            tabs: [secondTab],
            selectedTabID: sharedTabID
        )
        var session = BrowserSession(spaces: [first, second], selectedSpaceID: second.id)

        session.repairRuntimeIntegrity()

        XCTAssertEqual(Set(session.spaces.map(\.profile.id)).count, 2)
        XCTAssertEqual(Set(session.tabIDs).count, 2)
        XCTAssertEqual(session.selectedSpaceID, second.id)
        XCTAssertEqual(session.selectedTab?.title, BrowserTab.startPageTitle)
        XCTAssertEqual(session.selectedTab?.symbol, BrowserTab.startPageSymbol)
        XCTAssertNotEqual(session.spaces[0].selectedTabID, session.spaces[1].selectedTabID)
    }

    func testRuntimeRepairCreatesAUsableSelectionForEmptyOrDanglingState() {
        let emptySpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Empty",
            symbol: "circle",
            accent: .teal,
            folders: [],
            tabs: [],
            selectedTabID: TabID()
        )
        var session = BrowserSession(spaces: [emptySpace], selectedSpaceID: SpaceID())

        session.repairRuntimeIntegrity()

        XCTAssertEqual(session.selectedSpaceID, emptySpace.id)
        XCTAssertEqual(session.selectedSpace?.tabs.count, 1)
        XCTAssertEqual(session.selectedTab?.title, BrowserTab.startPageTitle)
        XCTAssertEqual(session.selectedTab?.symbol, BrowserTab.startPageSymbol)
        XCTAssertEqual(session.selectedTab?.placement, .current)

        var noSpaces = BrowserSession(spaces: [], selectedSpaceID: SpaceID())
        noSpaces.repairRuntimeIntegrity()
        XCTAssertEqual(noSpaces.spaces.count, 1)
        XCTAssertNotNil(noSpaces.selectedTab)
    }

    func testRuntimeRepairBoundsPinsHistoryFoldersAndArchivedIdentities() throws {
        let duplicateFolderID = FolderID()
        let cycleAID = FolderID()
        let cycleBID = FolderID()
        let folders = [
            SavedFolder(id: duplicateFolderID, title: "First"),
            SavedFolder(id: duplicateFolderID, title: "Second"),
            SavedFolder(id: cycleAID, title: "Cycle A", parentID: cycleBID),
            SavedFolder(id: cycleBID, title: "Cycle B", parentID: cycleAID),
            SavedFolder(title: "Orphan", parentID: FolderID()),
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
            history: history,
            selectedTabID: tabs[0].id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        session.repairRuntimeIntegrity()

        let repaired = try XCTUnwrap(session.selectedSpace)
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
        var firstWindow = BrowserWindowState(restoring: session)
        var secondWindow = BrowserWindowState(restoring: session)

        firstWindow.selectTab(workTabID, in: work.id, session: session)
        secondWindow.selectTab(personalTabID, in: personal.id, session: session)

        XCTAssertEqual(firstWindow.selectedSpaceID, work.id)
        XCTAssertEqual(firstWindow.selectedTab(in: session)?.id, workTabID)
        XCTAssertEqual(secondWindow.selectedSpaceID, personal.id)
        XCTAssertEqual(secondWindow.selectedTab(in: session)?.id, personalTabID)
        XCTAssertNotEqual(firstWindow.id, secondWindow.id)
    }

    func testRestoredBrowserWindowRepairsMissingSpaceAndTabSelections() throws {
        let session = BrowserSession.preview
        let selectedSpace = try XCTUnwrap(session.selectedSpace)
        let missingSpaceID = SpaceID()
        var window = BrowserWindowState(
            id: BrowserWindowID(),
            selectedSpaceID: missingSpaceID,
            selectedTabIDsBySpace: [
                missingSpaceID: TabID(),
                selectedSpace.id: TabID(),
            ]
        )

        window.repair(using: session)

        XCTAssertEqual(window.selectedSpaceID, session.selectedSpaceID)
        XCTAssertEqual(window.selectedTab(in: session)?.id, selectedSpace.selectedTabID)
        XCTAssertNil(window.selectedTabIDsBySpace[missingSpaceID])
    }

    func testBrowserWindowSelectionRoundTripsForSceneRestoration() throws {
        let session = BrowserSession.preview
        let personal = try XCTUnwrap(session.spaces.last)
        let selectedTabID = try XCTUnwrap(personal.tabs.first?.id)
        var window = BrowserWindowState(restoring: session)
        window.selectTab(selectedTabID, in: personal.id, session: session)

        let encoded = try JSONEncoder().encode(window)
        let restored = try JSONDecoder().decode(BrowserWindowState.self, from: encoded)

        XCTAssertEqual(restored, window)
        XCTAssertEqual(restored.selectedSpaceID, personal.id)
        XCTAssertEqual(restored.selectedTab(in: session)?.id, selectedTabID)
    }

    func testBrowserWindowChromeRoundTripsIndependentlyAndKeepsLegacySnapshotsReadable() throws {
        let session = BrowserSession.preview
        var firstWindow = BrowserWindowState(restoring: session)
        var secondWindow = BrowserWindowState(restoring: session)

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

    func testBrowserWindowSelectionSnapshotIgnoresPageMetadataChanges() {
        var session = BrowserSession.preview
        let windowID = BrowserWindowID()
        let originalSelection = BrowserWindowState(id: windowID, restoring: session)

        session.updateSelectedTab(
            url: URL(string: "https://example.com/updated"),
            title: "Updated page title"
        )

        XCTAssertEqual(
            BrowserWindowState(id: windowID, restoring: session),
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
        let firstWindow = BrowserWindowState(restoring: session)
        var secondWindow = BrowserWindowState(restoring: session)
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
}

final class BrowserTabStateArchiveTests: XCTestCase {
    func testEnvelopeRoundTripsItsPayloadStampAndURL() throws {
        let payload = Data((0..<2048).map { UInt8($0 % 251) })
        let url = try XCTUnwrap(URL(string: "https://example.com/reader?page=3#anchor"))

        let encoded = BrowserTabStateEnvelope(
            interactionState: payload,
            url: url
        ).encoded()
        let decoded = try XCTUnwrap(BrowserTabStateEnvelope.decode(encoded))

        XCTAssertEqual(decoded.interactionState, payload)
        XCTAssertEqual(decoded.url, url)
        XCTAssertEqual(decoded.formatVersion, BrowserTabStateEnvelope.currentFormatVersion)
        XCTAssertEqual(decoded.osBuild, BrowserTabStateEnvelope.currentOSBuild)
        XCTAssertTrue(decoded.isRestorable)
    }

    func testEnvelopeSurvivesAnAbsentURLAndAnEmptyPayload() throws {
        let encoded = BrowserTabStateEnvelope(
            interactionState: Data(),
            url: nil
        ).encoded()

        let decoded = try XCTUnwrap(BrowserTabStateEnvelope.decode(encoded))

        XCTAssertNil(decoded.url)
        XCTAssertTrue(decoded.interactionState.isEmpty)
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

        XCTAssertEqual(core.selectedSpaceID, session.selectedSpaceID)
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

    func testACoreSaveLeavesEveryHistoryKeyAndEveryFaviconAlone() async throws {
        let session = try makeRichLegacySession()
        let harness = makeHarness()
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()
        harness.recorder.reset()
        harness.favicons.reset()

        var retitled = session
        retitled.spaces[0].tabs[0].title = "Renamed by the page"
        harness.persistence.save(retitled, scope: .core)
        await harness.persistence.flushPendingSaves()

        XCTAssertEqual(harness.recorder.writtenKeys, [Storage.coreKey])
        XCTAssertTrue(harness.recorder.removedKeys.isEmpty)
        XCTAssertTrue(
            harness.favicons.reconciledTabIDs.isEmpty,
            "A core save must not touch icon bytes."
        )
        XCTAssertTrue(harness.favicons.pruneRequests.isEmpty)
    }

    func testAHistorySaveWritesOneSpaceAndNotTheCore() async throws {
        let session = try makeRichLegacySession()
        let harness = makeHarness()
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()
        harness.recorder.reset()
        harness.favicons.reset()

        var visited = session
        let visitedSpaceID = visited.spaces[0].id
        visited.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/just-now")),
            title: "Just now",
            in: visitedSpaceID,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        harness.persistence.save(visited, scope: .history(in: visitedSpaceID))
        await harness.persistence.flushPendingSaves()

        XCTAssertEqual(harness.recorder.writtenKeys, [Storage.historyKey(for: visitedSpaceID)])
        XCTAssertTrue(harness.favicons.reconciledTabIDs.isEmpty)
        let untouchedSpaceID = visited.spaces[1].id
        XCTAssertEqual(
            harness.recorder.byteCount(forKey: Storage.historyKey(for: untouchedSpaceID)),
            0,
            "Another Space's history is not this visit's business."
        )
    }

    func testAFaviconSaveReconcilesOneIconAndNeverRewritesHistory() async throws {
        let session = try makeRichLegacySession()
        let harness = makeHarness()
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()
        harness.recorder.reset()
        harness.favicons.reset()

        var captured = session
        let tabID = captured.spaces[0].tabs[0].id
        let capturedURL = try XCTUnwrap(captured.spaces[0].tabs[0].url)
        let capturedIcon = Self.faviconBytes(seed: 200, byteCount: 3_000)
        XCTAssertTrue(
            captured.cacheAutomaticTabFavicon(
                capturedIcon,
                iconAccent: BrowserTabIconAccent(red: 1, green: 0.25, blue: 0),
                url: capturedURL,
                tabID: tabID,
                in: captured.spaces[0].id
            )
        )
        harness.persistence.save(captured, scope: .favicon(for: tabID))
        await harness.persistence.flushPendingSaves()

        XCTAssertEqual(harness.favicons.reconciledTabIDs, [tabID])
        XCTAssertEqual(harness.favicons.favicon(tabID: tabID), capturedIcon)
        XCTAssertEqual(
            harness.recorder.writtenKeys,
            [Storage.coreKey],
            "An icon capture rewrites the core that frames it, and no history."
        )
    }

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
        harness.persistence.save(session, scope: .favicon(for: tabID))
        await harness.persistence.flushPendingSaves()

        let relaunched = makeHarness(
            defaults: harness.defaults,
            favicons: harness.favicons
        )
        let restored = try XCTUnwrap(relaunched.persistence.load())
        let restoredTab = restored.space(id: spaceID)?.tabs.first { $0.id == tabID }

        XCTAssertEqual(restoredTab?.faviconData, icon)
    }

    func testUnchangedPayloadsAreNotRewritten() async throws {
        let session = try makeRichLegacySession()
        let harness = makeHarness()
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()
        harness.recorder.reset()

        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()

        XCTAssertEqual(
            harness.recorder.writtenKeys,
            [],
            "A save that changed nothing must not write anything."
        )
    }

    func testRemovingASpaceDropsItsHistoryAndItsFavicons() async throws {
        let session = try makeRichLegacySession()
        let harness = makeHarness()
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()
        harness.recorder.reset()
        harness.favicons.reset()

        var reduced = session
        let removedSpace = try XCTUnwrap(reduced.spaces.last)
        let removedTabIDs = Set(
            removedSpace.tabs.map(\.id) + removedSpace.archivedTabs.map(\.tab.id)
        )
        XCTAssertNotNil(reduced.removeSpace(removedSpace.id))
        harness.persistence.save(reduced, scope: .core)
        await harness.persistence.flushPendingSaves()

        XCTAssertTrue(
            harness.recorder.removedKeys.contains(Storage.historyKey(for: removedSpace.id))
        )
        XCTAssertNil(harness.defaults.data(forKey: Storage.historyKey(for: removedSpace.id)))
        XCTAssertNotNil(
            harness.defaults.data(forKey: Storage.historyKey(for: reduced.spaces[0].id)),
            "A surviving Space keeps its history."
        )
        XCTAssertTrue(
            harness.favicons.storedTabIDs.isDisjoint(with: removedTabIDs),
            "A deleted Space must not leave its icons behind."
        )
    }

    func testClosingATabDropsItsFaviconFileAndKeepsOtherLiveFavicons() async throws {
        var session = BrowserSession.preview
        let spaceID = session.selectedSpaceID
        let closedTabID = try XCTUnwrap(
            session.selectedSpace?.currentTabs.first(where: { !$0.isStartPage })?.id
        )
        let keptTabID = try XCTUnwrap(
            session.selectedSpace?.tabs.first(where: { $0.id != closedTabID })?.id
        )
        let closedIcon = Data("closed-icon".utf8)
        let keptIcon = Data("kept-icon".utf8)
        let spaceIndex = try XCTUnwrap(session.spaces.firstIndex { $0.id == spaceID })
        let closedIndex = try XCTUnwrap(
            session.spaces[spaceIndex].tabs.firstIndex { $0.id == closedTabID }
        )
        let keptIndex = try XCTUnwrap(
            session.spaces[spaceIndex].tabs.firstIndex { $0.id == keptTabID }
        )
        session.spaces[spaceIndex].tabs[closedIndex].faviconData = closedIcon
        session.spaces[spaceIndex].tabs[keptIndex].faviconData = keptIcon
        let harness = makeHarness()
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()

        session.closeTab(closedTabID, at: Date(timeIntervalSince1970: 500))
        harness.persistence.save(session, scope: .core)
        await harness.persistence.flushPendingSaves()

        XCTAssertNil(harness.favicons.favicon(tabID: closedTabID))
        XCTAssertEqual(harness.favicons.favicon(tabID: keptTabID), keptIcon)
        XCTAssertNil(
            session.selectedSpace?.archivedTabs.first {
                $0.tab.id == closedTabID
            }?.tab.faviconData
        )
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

    func testTheCoreBlobCarriesNeitherHistoryNorIconBytes() async throws {
        let session = try makeRichLegacySession(
            historyEntriesPerSpace: 2_000,
            faviconByteCount: 12 * 1_024
        )
        let legacyByteCount = try JSONEncoder().encode(session).count

        let harness = makeHarness()
        harness.persistence.save(session)
        await harness.persistence.flushPendingSaves()
        let coreByteCount = try XCTUnwrap(harness.defaults.data(forKey: Storage.coreKey)).count

        harness.recorder.reset()
        var retitled = session
        retitled.spaces[0].tabs[0].title = "Mutated by the page"
        harness.persistence.save(retitled, scope: .core)
        await harness.persistence.flushPendingSaves()
        let titleChangeByteCount = harness.recorder.writtenByteCount

        let tabCount = session.spaces.reduce(0) { $0 + $1.tabs.count }
        print(
            """
            session-split measurement \
            (\(session.spaces.count) Spaces, \(tabCount) tabs, \
            2000 history entries per Space, 12 KB favicons)
              legacy v1 blob, written on every save: \(legacyByteCount) bytes
              v2 core blob:                          \(coreByteCount) bytes
              one title-change save now writes:      \(titleChangeByteCount) bytes
            """)

        XCTAssertLessThan(
            coreByteCount,
            legacyByteCount / 10,
            "The core must be a fraction of the blob it replaces."
        )
        XCTAssertLessThan(titleChangeByteCount, legacyByteCount / 10)
    }

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
            let spaceID = session.spaces[spaceIndex].id
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
            let renamedTabID = try XCTUnwrap(
                session.spaces[spaceIndex].tabs.last { !$0.isStartPage }?.id
            )
            XCTAssertTrue(
                session.setTabCustomTitle(
                    "Renamed in \(session.spaces[spaceIndex].name)",
                    tabID: renamedTabID,
                    in: spaceID,
                    at: epoch
                )
            )
            let archivedTabID = try XCTUnwrap(
                session.spaces[spaceIndex].currentTabs.first { !$0.isStartPage }?.id
            )
            XCTAssertTrue(session.closeExtensionTab(archivedTabID, in: spaceID, at: epoch))
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
        XCTAssertTrue(
            session.spaces.flatMap(\.archivedTabs).allSatisfy { $0.tab.faviconData == nil },
            "Closing a tab must release its cached favicon bytes."
        )
        return session
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
