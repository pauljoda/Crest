import Foundation
import XCTest

@testable import Crest

final class BrowserManualSetupPlanTests: XCTestCase {
    func testReorderingExistingSpacesPreservesContents() throws {
        var existing = makeSession()
        let firstID = try XCTUnwrap(existing.spaces.first?.id)
        let second = BrowserSession.makeBlankSpace(number: 2)
        existing.spaces.append(second)
        let secondID = second.id
        existing = try BrowserCoreSync.repair(existing)
        var plan = BrowserManualSetupPlan(existing: existing)

        plan.moveSpace(secondID, to: firstID)
        let preview = try plan.preview(mergingInto: existing)

        XCTAssertEqual(preview.spaces.map(\.id), [secondID, firstID])
        XCTAssertEqual(preview.defaultSpaceID, existing.defaultSpaceID)
        for space in existing.spaces {
            XCTAssertEqual(preview.space(id: space.id)?.tabs, space.tabs)
            XCTAssertEqual(preview.space(id: space.id)?.profile, space.profile)
        }
        plan.moveSpace(secondID, to: firstID)
        XCTAssertEqual(try plan.preview(mergingInto: existing).spaces.map(\.id), [firstID, secondID])
    }

    func testDraftOrderSurvivesResumeAndKeepsConcurrentlyAddedSpaces() throws {
        var existing = makeSession()
        let firstID = try XCTUnwrap(existing.spaces.first?.id)
        var plan = BrowserManualSetupPlan(existing: existing)
        let newID = try plan.addSpace()
        plan.moveSpace(newID, to: firstID)
        var resumed = try JSONDecoder().decode(
            BrowserManualSetupPlan.self, from: JSONEncoder().encode(plan))
        let concurrent = BrowserSession.makeBlankSpace(number: 2)
        existing.spaces.append(concurrent)
        let concurrentID = concurrent.id

        XCTAssertEqual(try resumed.preview(mergingInto: existing).spaces.map(\.id), [newID, firstID, concurrentID])
        resumed.reconcile(with: existing)
        XCTAssertEqual(try resumed.preview(mergingInto: existing).spaces.map(\.id), [newID, firstID, concurrentID])
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
        existing.spaces[0].tabs = (1...TabPlacement.pinnedCapacity).map { index in
            BrowserTab(
                title: "Pin \(index)",
                url: URL(string: "https://pin-\(index).example/"),
                placement: .pinned
            )
        }
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
            tabs: [BrowserTab.startPage()]
        )
        let refreshed = BrowserSession(spaces: [replacement])

        plan.reconcile(with: refreshed)

        XCTAssertFalse(plan.spaces.contains { $0.id == removedID })
        XCTAssertTrue(plan.spaces.contains { $0.id == draftedID && $0.isNew })
        XCTAssertTrue(plan.spaces.contains { $0.id == replacement.id && !$0.isNew })
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
            tabs: [tab]
        )
        return BrowserSession(
            spaces: [space],
            disposableSeedMarker: UUID()
        )
    }
}
