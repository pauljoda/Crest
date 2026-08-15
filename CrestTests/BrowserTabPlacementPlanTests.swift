import XCTest

@testable import Crest

final class BrowserTabPlacementPlanTests: XCTestCase {
    func testPinnedPlacementNormalizesDurabilityAndUsesPinnedSectionEnd() throws {
        let existingPinned = makeTab("Pinned", placement: .pinned)
        let saved = makeTab("Saved", placement: .saved)
        let current = makeTab("Current", placement: .current)
        let moving = makeTab(
            "Moving",
            url: URL(string: "https://example.com/moving"),
            placement: .current
        )
        let destination = makeSpace(tabs: [existingPinned, saved, current])

        let plan = try XCTUnwrap(
            BrowserTabPlacementPlan(
                moving: moving,
                to: .pinned,
                in: destination,
                among: destination.tabs
            )
        )
        let placed = plan.placing(moving)

        XCTAssertEqual(plan.placement, .pinned)
        XCTAssertNil(plan.folderID)
        XCTAssertEqual(plan.insertionIndex, 1)
        XCTAssertEqual(placed.savedURL, moving.url)
        XCTAssertNil(placed.folderID)
    }

    func testSavedPlacementUsesRequestedFolderAndItsLastMatchingTab() throws {
        let folder = SavedFolder(title: "Reading")
        let firstFiled = makeTab("First Filed", placement: .saved, folderID: folder.id)
        let rootSaved = makeTab("Root", placement: .saved)
        let lastFiled = makeTab("Last Filed", placement: .saved, folderID: folder.id)
        let current = makeTab("Current", placement: .current)
        let moving = makeTab("Moving", placement: .current)
        let destination = makeSpace(
            folders: [folder],
            tabs: [firstFiled, rootSaved, lastFiled, current]
        )

        let plan = try XCTUnwrap(
            BrowserTabPlacementPlan(
                moving: moving,
                to: .saved,
                folderID: folder.id,
                in: destination,
                among: destination.tabs
            )
        )

        XCTAssertEqual(plan.folderID, folder.id)
        XCTAssertEqual(plan.insertionIndex, 3)
        XCTAssertEqual(plan.placing(moving).folderID, folder.id)
    }

    func testUnknownFolderNormalizesToSavedRootAndUsesRootSectionEnd() throws {
        let existingFolder = SavedFolder(title: "Reading")
        let filed = makeTab("Filed", placement: .saved, folderID: existingFolder.id)
        let rootSaved = makeTab("Root", placement: .saved)
        let current = makeTab("Current", placement: .current)
        let moving = makeTab("Moving", placement: .current)
        let destination = makeSpace(
            folders: [existingFolder],
            tabs: [filed, rootSaved, current]
        )

        let plan = try XCTUnwrap(
            BrowserTabPlacementPlan(
                moving: moving,
                to: .saved,
                folderID: FolderID(),
                in: destination,
                among: destination.tabs
            )
        )

        XCTAssertNil(plan.folderID)
        XCTAssertEqual(plan.insertionIndex, 2)
        XCTAssertNil(plan.placing(moving).folderID)
    }

    func testCurrentPlacementClearsSavedMetadataAndAppendsToCurrentSection() throws {
        let existingCurrent = makeTab("Existing", placement: .current)
        let movingURL = try XCTUnwrap(URL(string: "https://example.com/saved"))
        let moving = BrowserTab(
            title: "Moving",
            url: movingURL,
            savedURL: movingURL,
            placement: .saved,
            folderID: FolderID()
        )
        let destination = makeSpace(tabs: [existingCurrent])

        let plan = try XCTUnwrap(
            BrowserTabPlacementPlan(
                moving: moving,
                to: .current,
                in: destination,
                among: destination.tabs
            )
        )
        let placed = plan.placing(moving)

        XCTAssertEqual(plan.insertionIndex, destination.tabs.endIndex)
        XCTAssertEqual(placed.placement, .current)
        XCTAssertNil(placed.savedURL)
        XCTAssertNil(placed.folderID)
    }

    func testMatchingBeforeTargetWinsOverSectionEnd() throws {
        let first = makeTab("First", placement: .current)
        let target = makeTab("Target", placement: .current)
        let last = makeTab("Last", placement: .current)
        let moving = makeTab("Moving", placement: .current)
        let destination = makeSpace(tabs: [first, target, last])

        let plan = try XCTUnwrap(
            BrowserTabPlacementPlan(
                moving: moving,
                to: .current,
                before: target.id,
                in: destination,
                among: destination.tabs
            )
        )

        XCTAssertEqual(plan.insertionIndex, 1)
    }

    func testNonmatchingBeforeTargetFallsBackToRequestedSectionEnd() throws {
        let saved = makeTab("Saved", placement: .saved)
        let firstCurrent = makeTab("First", placement: .current)
        let lastCurrent = makeTab("Last", placement: .current)
        let moving = makeTab("Moving", placement: .current)
        let destination = makeSpace(tabs: [saved, firstCurrent, lastCurrent])

        let plan = try XCTUnwrap(
            BrowserTabPlacementPlan(
                moving: moving,
                to: .current,
                before: saved.id,
                in: destination,
                among: destination.tabs
            )
        )

        XCTAssertEqual(plan.insertionIndex, destination.tabs.endIndex)
    }

    func testEmptySectionInsertionBoundariesAreExhaustive() throws {
        let pinned = makeTab("Pinned", placement: .pinned)
        let current = makeTab("Current", placement: .current)
        let destination = makeSpace(tabs: [pinned, current])
        let expectations: [(TabPlacement, Int)] = [
            (.pinned, 1),
            (.saved, 1),
            (.current, 2),
        ]

        for (placement, expectedIndex) in expectations {
            let moving = makeTab("Moving", placement: .current)
            let plan = try XCTUnwrap(
                BrowserTabPlacementPlan(
                    moving: moving,
                    to: placement,
                    in: destination,
                    among: destination.tabs
                )
            )

            XCTAssertEqual(
                plan.insertionIndex,
                expectedIndex,
                "Unexpected empty-section boundary for \(placement)"
            )
        }
    }

    func testPlanRejectsSelfDestinationAndPinnedOverflow() {
        let moving = makeTab("Moving", placement: .current)
        let ordinaryDestination = makeSpace(tabs: [])

        XCTAssertNil(
            BrowserTabPlacementPlan(
                moving: moving,
                to: .current,
                before: moving.id,
                in: ordinaryDestination,
                among: ordinaryDestination.tabs
            )
        )

        let fullPins = (0..<BrowserSpace.maximumPinnedTabs).map {
            makeTab("Pin \($0)", placement: .pinned)
        }
        let fullDestination = makeSpace(tabs: fullPins)

        XCTAssertNil(
            BrowserTabPlacementPlan(
                moving: moving,
                to: .pinned,
                in: fullDestination,
                among: fullDestination.tabs
            )
        )
    }

    func testPlanRejectsAnExistingDestinationTabWithTheMovingIdentity() {
        let moving = makeTab("Moving", placement: .current)
        let collision = BrowserTab(
            id: moving.id,
            title: "Existing destination",
            url: URL(string: "https://example.com/existing"),
            placement: .saved
        )
        let destination = makeSpace(tabs: [collision])

        XCTAssertNil(
            BrowserTabPlacementPlan(
                moving: moving,
                to: .pinned,
                in: destination,
                among: destination.tabs
            )
        )
    }

    func testSessionRejectsInvalidSpaceBoundariesWithoutMutation() {
        let moving = makeTab("Moving", placement: .current)
        let source = makeSpace(tabs: [moving])
        let destination = makeSpace(tabs: [])
        var session = BrowserSession(
            spaces: [source, destination],
            selectedSpaceID: source.id
        )
        let original = session
        let missingSpaceID = SpaceID()

        XCTAssertFalse(
            session.canMoveTab(
                moving.id,
                from: source.id,
                into: source.id
            )
        )
        XCTAssertFalse(
            session.canMoveTab(
                moving.id,
                from: source.id,
                into: missingSpaceID
            )
        )
        XCTAssertFalse(
            session.moveTab(
                moving.id,
                from: source.id,
                into: source.id
            )
        )
        XCTAssertFalse(
            session.moveTab(
                moving.id,
                from: missingSpaceID,
                into: destination.id
            )
        )
        XCTAssertEqual(session, original)
    }

    private func makeTab(
        _ title: String,
        url: URL? = nil,
        placement: TabPlacement,
        folderID: FolderID? = nil
    ) -> BrowserTab {
        BrowserTab(
            title: title,
            url: url,
            placement: placement,
            folderID: folderID
        )
    }

    private func makeSpace(
        folders: [SavedFolder] = [],
        tabs: [BrowserTab]
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Destination",
            symbol: "square",
            accent: .indigo,
            folders: folders,
            tabs: tabs,
            selectedTabID: tabs.last?.id
        )
    }
}
