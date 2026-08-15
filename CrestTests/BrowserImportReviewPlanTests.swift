import Foundation
import XCTest

@testable import Crest

final class BrowserImportReviewPlanTests: XCTestCase {
    func testSourcePreviewPartitionsTabsAndFoldersInOneModel() {
        let folder = SavedFolder(title: "Reading")
        let pinned = BrowserTab(title: "Pinned", url: nil, placement: .pinned)
        let filed = BrowserTab(
            title: "Filed",
            url: nil,
            placement: .saved,
            folderID: folder.id
        )
        let unfiled = BrowserTab(title: "Unfiled", url: nil, placement: .saved)
        let current = BrowserTab(title: "Current", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Imported",
            symbol: "square.and.arrow.down",
            accent: .indigo,
            folders: [folder],
            tabs: [pinned, filed, unfiled, current],
            selectedTabID: current.id
        )
        let review = BrowserImportSpaceReview(
            sourceSpace: space,
            destination: .newSpace,
            customization: BrowserImportSpaceCustomization(space: space),
            includedTabIDs: Set(space.tabs.map(\.id)),
            duplicateTabIDs: [],
            placementOverrides: [:],
            spaceInclusionOverride: nil,
            passwordInclusionOverride: nil
        )

        let sections = BrowserSourceImportPreviewSections(review: review)

        XCTAssertEqual(sections.pinnedTabs.map(\.id), [pinned.id])
        XCTAssertEqual(sections.currentTabs.map(\.id), [current.id])
        XCTAssertEqual(sections.unfiledSavedTabs.map(\.id), [unfiled.id])
        XCTAssertEqual(
            sections.savedTabsByFolderID[folder.id]?.map(\.id),
            [filed.id]
        )
    }

    func testPlanMatchesSpaceNamesSkipsDuplicateTabsAndFlagsPinnedOverflow() throws {
        let existing = makeExistingSession()
        let importedSpace = makeImportedSpace(name: " work ")
        let imported = makeImport(spaces: [importedSpace])

        let plan = BrowserImportReviewPlan(imported: imported, existing: existing)
        let review = try XCTUnwrap(plan.spaces.first)

        XCTAssertEqual(review.destination, .existing(existing.spaces[0].id))
        XCTAssertEqual(
            review.duplicateTabIDs,
            Set([importedSpace.tabs[0].id])
        )
        XCTAssertFalse(review.includedTabIDs.contains(importedSpace.tabs[0].id))
        XCTAssertEqual(
            plan.overflowTabIDs(in: existing),
            Set(importedSpace.tabs.suffix(2).map(\.id))
        )

        let preview = try plan.preview(mergingInto: existing)
        let merged = try XCTUnwrap(preview.space(id: existing.spaces[0].id))
        XCTAssertEqual(merged.profile, existing.spaces[0].profile)
        XCTAssertEqual(merged.pinnedTabs.count, BrowserSpace.maximumPinnedTabs)
        XCTAssertEqual(
            merged.tabs.filter { $0.url == URL(string: "https://duplicate.example/") }.count,
            1
        )
        let overflowFolder = try XCTUnwrap(
            merged.folders.first { $0.title == "Imported Pinned Tabs" }
        )
        XCTAssertEqual(
            merged.savedTabs.filter { $0.folderID == overflowFolder.id }.map(\.title),
            ["Pin 11", "Pin 12"]
        )
    }

    func testPlanCanCreateANewSpaceAndExplicitlyIncludeADuplicate() throws {
        let existing = makeExistingSession()
        let importedSpace = makeImportedSpace(name: "Work")
        let imported = makeImport(spaces: [importedSpace])
        var plan = BrowserImportReviewPlan(imported: imported, existing: existing)

        plan.setDestination(.newSpace, for: importedSpace.id)
        plan.setTab(importedSpace.tabs[0].id, isIncluded: true, in: importedSpace.id)

        let preview = try plan.preview(mergingInto: existing)

        XCTAssertEqual(preview.spaces.count, 2)
        XCTAssertEqual(preview.spaces[1].name, "Work")
        XCTAssertTrue(preview.spaces[1].tabs.contains { $0.title == "Duplicate" })
        XCTAssertEqual(preview.spaces[1].pinnedTabs.count, BrowserSpace.maximumPinnedTabs)
    }

    func testPlacementOverrideMovesAnImportedTabBetweenPreviewSections() throws {
        let existing = makeExistingSession()
        let importedSpace = makeImportedSpace(name: "Another")
        let imported = makeImport(spaces: [importedSpace])
        var plan = BrowserImportReviewPlan(imported: imported, existing: existing)
        let duplicate = importedSpace.tabs[0]

        plan.setPlacement(.saved, for: duplicate.id, in: importedSpace.id)

        let preview = try plan.preview(mergingInto: existing)
        let created = try XCTUnwrap(preview.spaces.last)
        XCTAssertEqual(created.tabs.first { $0.title == "Duplicate" }?.placement, .saved)
    }

    func testCustomizationEditsMatchedDestinationWithoutReplacingItsProfile() throws {
        let existing = makeExistingSession()
        let importedSpace = makeImportedSpace(name: "Work")
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )
        var branding = existing.spaces[0].branding
        branding.colors = [.ocean, .gold]

        plan.setSpaceIdentity(
            name: "Focused Work",
            symbol: "hammer.fill",
            for: importedSpace.id
        )
        plan.setSpaceBranding(branding, for: importedSpace.id)

        let preview = try plan.preview(mergingInto: existing)
        let merged = try XCTUnwrap(preview.spaces.first)
        XCTAssertEqual(merged.profile, existing.spaces[0].profile)
        XCTAssertEqual(merged.name, "Focused Work")
        XCTAssertEqual(merged.symbol, "hammer.fill")
        XCTAssertEqual(merged.branding, branding.normalized())
    }

    func testPlanCanBulkExcludeAndRestoreOpenTabsWithoutChangingSavedTabs() throws {
        let existing = makeExistingSession()
        var importedSpace = makeImportedSpace(name: "Another")
        importedSpace.tabs.append(
            BrowserTab(
                title: "Second Open Tab",
                url: URL(string: "https://open.example/"),
                placement: .current
            )
        )
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )
        let openTabIDs = Set(
            importedSpace.currentTabs.map(\.id)
        )

        plan.setTabs(openTabIDs, isIncluded: false, in: importedSpace.id)
        var review = try XCTUnwrap(plan.spaces.first)
        XCTAssertTrue(review.includedTabIDs.isDisjoint(with: openTabIDs))
        XCTAssertEqual(
            review.includedTabIDs.intersection(Set(importedSpace.pinnedTabs.map(\.id))).count,
            importedSpace.pinnedTabs.count
        )

        plan.setTabs(openTabIDs, isIncluded: true, in: importedSpace.id)
        review = try XCTUnwrap(plan.spaces.first)
        XCTAssertTrue(openTabIDs.isSubset(of: review.includedTabIDs))
    }

    func testWholeSpaceCanBeDroppedAndRestoredWithoutReimportingKnownDuplicates() throws {
        let existing = makeExistingSession()
        let importedSpace = makeImportedSpace(name: "Work")
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )
        let originalIncluded = try XCTUnwrap(plan.spaces.first).includedTabIDs

        plan.setSpace(importedSpace.id, isIncluded: false)
        var review = try XCTUnwrap(plan.spaces.first)
        XCTAssertFalse(review.isIncluded)
        XCTAssertTrue(review.includedTabIDs.isEmpty)

        plan.setSpace(importedSpace.id, isIncluded: true)
        review = try XCTUnwrap(plan.spaces.first)
        XCTAssertTrue(review.isIncluded)
        XCTAssertEqual(review.includedTabIDs, originalIncluded)
        XCTAssertTrue(
            review.includedTabIDs.isDisjoint(with: review.duplicateTabIDs)
        )
    }

    @MainActor
    func testExcludedArcSpaceCannotReachPreviewOrCommittedSession() throws {
        let existing = makeExistingSession()
        let included = makeSpace(
            name: "Research",
            symbol: "book.fill",
            accent: .teal,
            tabs: [
                BrowserTab(
                    title: "Keep",
                    url: URL(string: "https://keep.example/"),
                    placement: .current
                )
            ]
        )
        let excluded = makeSpace(
            name: "Private",
            symbol: "lock.fill",
            accent: .orange,
            tabs: [
                BrowserTab(
                    title: "Leave Behind",
                    url: URL(string: "https://excluded.example/"),
                    placement: .current
                )
            ]
        )
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [included, excluded]),
            existing: existing
        )
        plan.setSpace(excluded.id, isIncluded: false)

        let preview = try plan.preview(mergingInto: existing)
        XCTAssertNotNil(preview.space(id: included.id))
        XCTAssertNil(preview.space(id: excluded.id))
        XCTAssertFalse(preview.spaces.contains { $0.name == excluded.name })

        let persistence = InMemoryBrowserSessionPersistence()
        let browser = BrowserStore(session: existing, persistence: persistence)
        try browser.commitReviewedImport(plan)

        XCTAssertEqual(browser.session, preview)
        XCTAssertEqual(persistence.session, preview)
    }

    func testDuplicateOnlySpaceRemainsIncludedUntilItIsExplicitlyDropped() throws {
        let existing = makeExistingSession()
        let duplicate = BrowserTab(
            title: "Duplicate",
            url: URL(string: "https://duplicate.example/"),
            placement: .current
        )
        let importedSpace = makeSpace(
            name: "Work",
            symbol: "briefcase",
            accent: .indigo,
            tabs: [duplicate]
        )
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )

        var review = try XCTUnwrap(plan.spaces.first)
        XCTAssertTrue(review.includedTabIDs.isEmpty)
        XCTAssertTrue(review.isIncluded)

        plan.setSpace(importedSpace.id, isIncluded: false)
        review = try XCTUnwrap(plan.spaces.first)
        XCTAssertFalse(review.isIncluded)
    }

    func testPasswordsCanBeIncludedPerSpaceAndAreDisabledWhenTheSpaceIsDropped() throws {
        let importedSpace = makeImportedSpace(name: "Work")
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: makeExistingSession()
        )

        XCTAssertTrue(try XCTUnwrap(plan.spaces.first).includesPasswords)

        plan.setPasswords(false, in: importedSpace.id)
        XCTAssertFalse(try XCTUnwrap(plan.spaces.first).includesPasswords)

        plan.setPasswords(true, in: importedSpace.id)
        XCTAssertTrue(try XCTUnwrap(plan.spaces.first).includesPasswords)

        plan.setSpace(importedSpace.id, isIncluded: false)
        XCTAssertFalse(try XCTUnwrap(plan.spaces.first).includesPasswords)
    }

    func testDuplicateExplanationTracksTheSelectedExistingDestination() throws {
        let existing = makeExistingSession()
        let importedSpace = makeImportedSpace(name: "Work")
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )
        let duplicateID = importedSpace.tabs[0].id

        XCTAssertEqual(plan.duplicateTabIDs(in: existing), Set([duplicateID]))

        plan.setDestination(.newSpace, for: importedSpace.id)
        XCTAssertTrue(plan.duplicateTabIDs(in: existing).isEmpty)
    }

    func testMatchedDestinationTabsIdentifyTheOtherSideOfADuplicatePair() throws {
        let existing = makeExistingSession()
        let importedSpace = makeImportedSpace(name: "Work")
        let plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )

        XCTAssertEqual(
            plan.matchedDestinationTabIDs(
                for: importedSpace.id,
                in: existing
            ),
            Set([existing.spaces[0].tabs[0].id])
        )
    }

    @MainActor
    func testPasswordCommitterStoresPasswordsInTheMatchedSpaceWithoutDuplicates() async throws {
        let existing = makeExistingSession()
        let importedSpace = makeImportedSpace(name: "Work")
        let plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )
        let vault = InMemoryCredentialVault()
        let browser = BrowserStore(
            session: existing,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: vault
        )
        let origin = try XCTUnwrap(
            CredentialOrigin(url: URL(string: "https://accounts.example.com/login")!)
        )
        let password = BrowserImportedPassword(
            sourceApplication: .chrome,
            sourceProfileID: "Profile 1",
            sourceProfileName: "Work",
            origin: origin,
            username: "paul@example.com",
            password: "secret"
        )

        try browser.commitReviewedImport(plan)
        let first = await BrowserPasswordImportCommitter.commit(
            [password],
            plan: plan,
            browser: browser
        )
        let second = await BrowserPasswordImportCommitter.commit(
            [password],
            plan: plan,
            browser: browser
        )
        let descriptors = try await browser.savedCredentialDescriptors(
            in: existing.spaces[0].id
        )

        XCTAssertEqual(first, BrowserPasswordImportResult(importedCount: 1, skippedCount: 0))
        XCTAssertEqual(second, BrowserPasswordImportResult(importedCount: 0, skippedCount: 1))
        XCTAssertEqual(descriptors.map(\.username), ["paul@example.com"])
    }

    @MainActor
    func testArcPasswordScopesToEveryIncludedSpaceContainingItsSite() throws {
        let sharedURL = URL(string: "https://accounts.example.com/login")!
        let firstTab = BrowserTab(
            title: "Account",
            url: sharedURL,
            placement: .saved
        )
        let secondTab = BrowserTab(
            title: "Dashboard",
            url: URL(string: "https://accounts.example.com/dashboard"),
            placement: .current
        )
        let droppedTab = BrowserTab(
            title: "Dropped",
            url: sharedURL,
            placement: .current
        )
        let spaces = [
            makeSpace(name: "Work", symbol: "briefcase", accent: .indigo, tabs: [firstTab]),
            makeSpace(name: "Personal", symbol: "person", accent: .teal, tabs: [secondTab]),
            makeSpace(name: "Archive", symbol: "archivebox", accent: .orange, tabs: [droppedTab]),
        ]
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: spaces),
            existing: BrowserSession(spaces: [], selectedSpaceID: SpaceID())
        )
        plan.setSpace(spaces[2].id, isIncluded: false)
        plan.setPasswords(false, in: spaces[1].id)
        let password = BrowserImportedPassword(
            sourceApplication: .arc,
            sourceProfileID: "Profile 1",
            sourceProfileName: "Arc",
            origin: try XCTUnwrap(CredentialOrigin(url: sharedURL)),
            username: "paul@example.com",
            password: "secret"
        )

        XCTAssertEqual(
            Set(
                BrowserPasswordImportCommitter.destinationSpaceIDs(
                    for: password,
                    plan: plan
                )),
            Set([spaces[0].id])
        )

        let unmatchedPassword = BrowserImportedPassword(
            sourceApplication: .arc,
            sourceProfileID: "Profile 1",
            sourceProfileName: "Arc",
            origin: try XCTUnwrap(
                CredentialOrigin(
                    url: URL(string: "https://unmatched.example/login")!
                )),
            username: "paul@example.com",
            password: "secret"
        )
        XCTAssertTrue(
            BrowserPasswordImportCommitter.destinationSpaceIDs(
                for: unmatchedPassword,
                plan: plan
            ).isEmpty
        )
    }

    func testMergeReusesMatchingFolderAndDoesNotCreateExcludedFolders() throws {
        let existingReadingFolder = SavedFolder(title: "Reading", symbol: "books.vertical")
        var existing = makeExistingSession()
        existing.spaces[0].folders = [existingReadingFolder]

        let sourceReadingFolder = SavedFolder(title: " reading ", symbol: "book")
        let excludedFolder = SavedFolder(title: "Leave Behind", symbol: "archivebox")
        let includedTab = BrowserTab(
            title: "Article",
            url: URL(string: "https://article.example/"),
            placement: .saved,
            folderID: sourceReadingFolder.id
        )
        let excludedTab = BrowserTab(
            title: "Excluded",
            url: URL(string: "https://excluded.example/"),
            placement: .saved,
            folderID: excludedFolder.id
        )
        let importedSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [sourceReadingFolder, excludedFolder],
            tabs: [includedTab, excludedTab],
            selectedTabID: includedTab.id
        )
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )

        plan.setTab(excludedTab.id, isIncluded: false, in: importedSpace.id)

        let preview = try plan.preview(mergingInto: existing)
        let merged = try XCTUnwrap(preview.spaces.first)
        XCTAssertEqual(merged.folders, [existingReadingFolder])
        XCTAssertEqual(
            merged.tabs.first(where: { $0.id == includedTab.id })?.folderID,
            existingReadingFolder.id
        )
        XCTAssertFalse(merged.tabs.contains(where: { $0.id == excludedTab.id }))
    }

    func testNewSpaceContainsOnlyFoldersUsedByIncludedTabs() throws {
        let usedFolder = SavedFolder(title: "Used")
        let unusedFolder = SavedFolder(title: "Unused")
        let includedTab = BrowserTab(
            title: "Keep",
            url: URL(string: "https://keep.example/"),
            placement: .saved,
            folderID: usedFolder.id
        )
        let excludedTab = BrowserTab(
            title: "Leave",
            url: URL(string: "https://leave.example/"),
            placement: .saved,
            folderID: unusedFolder.id
        )
        let importedSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Research",
            symbol: "book.fill",
            accent: .indigo,
            folders: [usedFolder, unusedFolder],
            tabs: [includedTab, excludedTab],
            selectedTabID: includedTab.id
        )
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: BrowserSession(spaces: [], selectedSpaceID: SpaceID())
        )

        plan.setTab(excludedTab.id, isIncluded: false, in: importedSpace.id)

        let preview = try plan.preview(
            mergingInto: BrowserSession(spaces: [], selectedSpaceID: SpaceID())
        )
        let created = try XCTUnwrap(preview.spaces.first)
        XCTAssertEqual(created.folders, [usedFolder])
        XCTAssertEqual(created.savedTabs.map(\.id), [includedTab.id])
    }

    private func makeExistingSession() -> BrowserSession {
        let existingTabs = [
            BrowserTab(
                title: "Duplicate",
                url: URL(string: "https://duplicate.example/"),
                placement: .current
            ),
            BrowserTab(
                title: "Existing Pin 1",
                url: URL(string: "https://existing-pin-1.example/"),
                placement: .pinned
            ),
            BrowserTab(
                title: "Existing Pin 2",
                url: URL(string: "https://existing-pin-2.example/"),
                placement: .pinned
            ),
        ]
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: existingTabs,
            selectedTabID: existingTabs[0].id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }

    func testAnImportThatLandsContentClearsTheDisposableSeedMarker() throws {
        let seeded = makeSeededSession()
        XCTAssertTrue(seeded.hasDisposableSeedState)
        let importedSpace = makeResearchSpace()
        let plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: seeded
        )

        let preview = try plan.preview(mergingInto: seeded)

        XCTAssertNil(
            preview.disposableSeedMarker,
            "The marker gates every sync stage, so an imported Space that kept it never syncs."
        )
        XCTAssertFalse(preview.hasDisposableSeedState)
        XCTAssertTrue(preview.spaces.contains { $0.name == "Research" })
    }

    func testAnImportEveryoneOptedOutOfLeavesAFreshInstallAFreshInstall() throws {
        let seeded = makeSeededSession()
        let importedSpace = makeResearchSpace()
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: seeded
        )
        plan.setSpace(importedSpace.id, isIncluded: false)

        let preview = try plan.preview(mergingInto: seeded)

        XCTAssertTrue(
            preview.hasDisposableSeedState,
            "Nothing landed, so nothing graduated out of the fresh-install state."
        )
    }

    func testABlankReviewedSpaceNameAndSymbolFallBackInsteadOfCommittingEmpty() throws {
        let existing = makeExistingSession()
        let importedSpace = makeResearchSpace()
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )
        plan.setSpaceIdentity(name: "   ", symbol: "\n", for: importedSpace.id)

        let preview = try plan.preview(mergingInto: existing)
        let created = try XCTUnwrap(preview.space(id: importedSpace.id))

        XCTAssertEqual(created.name, BrowserImportSpaceCustomization.fallbackName)
        XCTAssertEqual(created.symbol, BrowserImportSpaceCustomization.fallbackSymbol)
    }

    func testAReviewedSpaceNameKeepsItsInnerSpacingButLosesItsEdges() throws {
        let existing = makeExistingSession()
        let importedSpace = makeResearchSpace()
        var plan = BrowserImportReviewPlan(
            imported: makeImport(spaces: [importedSpace]),
            existing: existing
        )
        plan.setSpaceIdentity(
            name: "  Deep  Work  ",
            symbol: " star.fill ",
            for: importedSpace.id
        )

        let preview = try plan.preview(mergingInto: existing)
        let created = try XCTUnwrap(preview.space(id: importedSpace.id))

        XCTAssertEqual(created.name, "Deep  Work")
        XCTAssertEqual(created.symbol, "star.fill")
    }

    private func makeSeededSession() -> BrowserSession {
        var seeded = BrowserSession.freshInstallSeed
        seeded.repairRuntimeIntegrity()
        return seeded
    }

    private func makeResearchSpace() -> BrowserSpace {
        let tab = BrowserTab(
            title: "Swift",
            url: URL(string: "https://swift.org/"),
            placement: .saved
        )
        return makeSpace(
            name: "Research",
            symbol: "books.vertical.fill",
            accent: .teal,
            tabs: [tab]
        )
    }

    private func makeImportedSpace(name: String) -> BrowserSpace {
        var tabs = [
            BrowserTab(
                title: "Duplicate",
                url: URL(string: "https://duplicate.example/"),
                placement: .current
            )
        ]
        tabs.append(
            contentsOf: (1...12).map { index in
                BrowserTab(
                    title: "Pin \(index)",
                    url: URL(string: "https://pin-\(index).example/"),
                    placement: .pinned
                )
            })
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: "sidebar.left",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs[0].id
        )
    }

    private func makeSpace(
        name: String,
        symbol: String,
        accent: SpaceAccent,
        tabs: [BrowserTab]
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: symbol,
            accent: accent,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs.first?.id
        )
    }

    private func makeImport(spaces: [BrowserSpace]) -> BrowserPortableImport {
        BrowserPortableImport(
            spaces: spaces,
            summary: BrowserPortableImportSummary(
                spaceCount: spaces.count,
                folderCount: spaces.reduce(0) { $0 + $1.folders.count },
                liveTabCount: spaces.reduce(0) { $0 + $1.tabs.count },
                archivedTabCount: 0,
                historyEntryCount: 0
            )
        )
    }
}
