import Foundation
import XCTest
@testable import Crest

final class BrowserManualSetupPlanTests: XCTestCase {
    func testDiscardingAddedTabsKeepsSpaceCustomization() throws {
        let existing = BrowserSession.preview
        var plan = BrowserManualSetupPlan(existing: existing)
        let spaceID = try XCTUnwrap(plan.spaces.first?.id)
        plan.setSpaceIdentity(name: "Renamed", symbol: "star.fill", for: spaceID)
        _ = try plan.addTab(
            title: "Example",
            url: try XCTUnwrap(URL(string: "https://example.com")),
            placement: .pinned,
            to: spaceID
        )

        plan.discardAddedTabs()

        let draft = try XCTUnwrap(plan.spaces.first)
        XCTAssertEqual(draft.customization.name, "Renamed")
        XCTAssertEqual(draft.customization.symbol, "star.fill")
        XCTAssertTrue(draft.addedTabs.isEmpty)
    }

    func testPreviewPreservesExistingTabsWhileApplyingEditsAndManualTabs() throws {
        let existing = makeSession()
        let space = try XCTUnwrap(existing.spaces.first)
        var plan = BrowserManualSetupPlan(existing: existing)
        var branding = space.branding
        branding.colors = [.ocean, .gold]

        plan.setSpaceIdentity(
            name: "Focused Work",
            symbol: "hammer.fill",
            for: space.id
        )
        plan.setSpaceBranding(branding, for: space.id)
        _ = try plan.addTab(
            input: "swift.org",
            placement: .saved,
            to: space.id,
            at: Date(timeIntervalSince1970: 10)
        )

        let preview = try plan.preview(mergingInto: existing)
        let edited = try XCTUnwrap(preview.space(id: space.id))

        XCTAssertEqual(edited.name, "Focused Work")
        XCTAssertEqual(edited.symbol, "hammer.fill")
        XCTAssertEqual(edited.branding, branding.normalized())
        XCTAssertEqual(edited.profile.id, space.profile.id)
        XCTAssertTrue(edited.tabs.contains { $0.title == "Existing" })
        XCTAssertEqual(edited.savedTabs.map(\.url), [URL(string: "https://swift.org")])
        XCTAssertNil(preview.disposableSeedMarker)
    }

    func testPlanCreatesANewSpaceWithPinnedSavedAndOpenTabs() throws {
        let existing = makeSession()
        let existingSpace = try XCTUnwrap(existing.spaces.first)
        var plan = BrowserManualSetupPlan(existing: existing)
        let newSpaceID = try plan.addSpace()

        _ = try plan.addTab(input: "apple.com", placement: .pinned, to: newSpaceID)
        _ = try plan.addTab(input: "swift.org", placement: .saved, to: newSpaceID)
        _ = try plan.addTab(input: "example.com", placement: .current, to: newSpaceID)

        let preview = try plan.preview(mergingInto: existing)
        let created = try XCTUnwrap(preview.space(id: newSpaceID))

        XCTAssertEqual(preview.spaces.count, existing.spaces.count + 1)
        XCTAssertEqual(
            preview.space(id: existingSpace.id)?.profile.id,
            existingSpace.profile.id
        )
        XCTAssertEqual(created.pinnedTabs.map(\.url), [URL(string: "https://apple.com")])
        XCTAssertEqual(created.savedTabs.map(\.url), [URL(string: "https://swift.org")])
        XCTAssertEqual(created.currentTabs.map(\.url), [URL(string: "https://example.com")])
        XCTAssertEqual(created.selectedTabID, created.currentTabs.first?.id)
    }

    func testRemovingANewSpaceDoesNotAllowRemovingAnExistingSpace() throws {
        let existing = makeSession()
        let existingID = try XCTUnwrap(existing.spaces.first?.id)
        var plan = BrowserManualSetupPlan(existing: existing)
        let newSpaceID = try plan.addSpace()

        XCTAssertFalse(plan.removeSpace(existingID))
        XCTAssertTrue(plan.removeSpace(newSpaceID))
        XCTAssertEqual(plan.spaces.map(\.id), [existingID])
    }

    func testPlanRejectsInvalidAddressesAndPinnedOverflow() throws {
        var existing = makeSession()
        let spaceID = try XCTUnwrap(existing.spaces.first?.id)
        existing.spaces[0].tabs = (1...BrowserSpace.maximumPinnedTabs).map { index in
            BrowserTab(
                title: "Pin \(index)",
                url: URL(string: "https://pin-\(index).example/"),
                placement: .pinned
            )
        }
        existing.spaces[0].selectedTabID = existing.spaces[0].tabs.first?.id
        var plan = BrowserManualSetupPlan(existing: existing)

        XCTAssertThrowsError(
            try plan.addTab(input: "   ", placement: .current, to: spaceID)
        ) { error in
            XCTAssertEqual(error as? BrowserManualSetupError, .invalidAddress)
        }
        XCTAssertThrowsError(
            try plan.addTab(input: "overflow.example", placement: .pinned, to: spaceID)
        ) { error in
            XCTAssertEqual(error as? BrowserManualSetupError, .pinnedLimitReached)
        }
    }

    func testPlanRoundTripsForWizardResume() throws {
        let existing = makeSession()
        var plan = BrowserManualSetupPlan(existing: existing)
        let newSpaceID = try plan.addSpace()
        _ = try plan.addTab(input: "crest.app", placement: .saved, to: newSpaceID)

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(BrowserManualSetupPlan.self, from: data)

        XCTAssertEqual(decoded, plan)
    }

    func testDraftStoreSavesLoadsAndClearsAResumablePlan() throws {
        let suiteName = "BrowserManualSetupDraftStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var plan = BrowserManualSetupPlan(existing: makeSession())
        _ = try plan.addSpace()

        BrowserManualSetupDraftStore.save(plan, defaults: defaults)
        XCTAssertEqual(
            BrowserManualSetupDraftStore.load(defaults: defaults),
            plan
        )

        BrowserManualSetupDraftStore.clear(defaults: defaults)
        XCTAssertNil(BrowserManualSetupDraftStore.load(defaults: defaults))
    }

    func testReconcileDropsRemovedSpacesAndIncludesNewExistingSpaces() throws {
        var existing = makeSession()
        var plan = BrowserManualSetupPlan(existing: existing)
        let removedID = try XCTUnwrap(existing.spaces.first?.id)
        existing.addSpace()
        let addedID = existing.selectedSpaceID
        existing.spaces.removeAll { $0.id == removedID }
        existing.selectedSpaceID = addedID

        plan.reconcile(with: existing)

        XCTAssertFalse(plan.spaces.contains { $0.id == removedID })
        XCTAssertTrue(plan.spaces.contains { $0.id == addedID && !$0.isNew })
    }

    func testResumeReconcilesExistingSpacesWithoutDiscardingNewDrafts() throws {
        let original = makeSession()
        let removedID = try XCTUnwrap(original.spaces.first?.id)
        var plan = BrowserManualSetupPlan(existing: original)
        let draftedID = try plan.addSpace()

        let replacement = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Synced Space",
            symbol: "icloud.fill",
            accent: .teal,
            folders: [],
            tabs: [BrowserTab.startPage()],
            selectedTabID: nil
        )
        let refreshed = BrowserSession(
            spaces: [replacement],
            selectedSpaceID: replacement.id
        )

        plan.reconcile(with: refreshed)

        XCTAssertFalse(plan.spaces.contains { $0.id == removedID })
        XCTAssertTrue(plan.spaces.contains { $0.id == draftedID && $0.isNew })
        XCTAssertTrue(plan.spaces.contains { $0.id == replacement.id && !$0.isNew })
    }

    func testABlankIdentityFallsBackForANewSpaceJustAsItDoesForAnEditedOne() throws {
        let existing = makeSession()
        let editedID = try XCTUnwrap(existing.spaces.first?.id)
        var plan = BrowserManualSetupPlan(existing: existing)
        let newSpaceID = try plan.addSpace()
        plan.setSpaceIdentity(name: "  ", symbol: "  ", for: newSpaceID)
        plan.setSpaceIdentity(name: "\t", symbol: "\n", for: editedID)

        let preview = try plan.preview(mergingInto: existing)
        let created = try XCTUnwrap(preview.space(id: newSpaceID))
        let edited = try XCTUnwrap(preview.space(id: editedID))

        XCTAssertEqual(created.name, BrowserImportSpaceCustomization.fallbackName)
        XCTAssertEqual(created.symbol, BrowserImportSpaceCustomization.fallbackSymbol)
        XCTAssertEqual(edited.name, BrowserImportSpaceCustomization.fallbackName)
        XCTAssertEqual(edited.symbol, BrowserImportSpaceCustomization.fallbackSymbol)
    }

    private func makeSession() -> BrowserSession {
        let tab = BrowserTab(
            title: "Existing",
            url: URL(string: "https://existing.example/"),
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        return BrowserSession(
            spaces: [space],
            selectedSpaceID: space.id,
            disposableSeedMarker: UUID()
        )
    }
}
