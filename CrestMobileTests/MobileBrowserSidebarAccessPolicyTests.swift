import XCTest

@testable import CrestMobile

@MainActor
final class BrowserSidebarAccessPolicyTests: XCTestCase {
    func testLockedSelectedSpaceHidesItsActionsUntilExactProfileUnlock() async {
        let context = makeContext(sourceIsProtected: true)

        XCTAssertFalse(
            BrowserSidebarAccessPolicy.showsSelectedSpaceActions(
                in: context.browser,
                accessController: context.access
            )
        )
        let didUnlock = await context.access.unlock(context.source)
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(
            BrowserSidebarAccessPolicy.showsSelectedSpaceActions(
                in: context.browser,
                accessController: context.access
            )
        )

        context.browser.session.spaces[0] = replacingProfile(
            in: context.source,
            with: Self.uuid(9)
        )
        XCTAssertFalse(
            BrowserSidebarAccessPolicy.showsSelectedSpaceActions(
                in: context.browser,
                accessController: context.access
            )
        )
    }

    func testDeletingSpaceIsExcludedFromPickerAndDropDestinations() {
        let context = makeContext()
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.destination.id))
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }

        XCTAssertEqual(
            BrowserSidebarAccessPolicy.availableSpaces(in: context.browser)
                .map(\.id),
            [context.source.id]
        )
        XCTAssertNil(
            BrowserSidebarAccessPolicy.unlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: context.destination),
                in: context.browser,
                accessController: context.access
            )
        )
    }

    func testLockedDestinationRemainsVisibleButRejectsTabDrops() {
        let context = makeContext(destinationIsProtected: true)

        XCTAssertEqual(
            BrowserSidebarAccessPolicy.availableSpaces(in: context.browser)
                .map(\.id),
            [context.source.id, context.destination.id]
        )
        XCTAssertNil(
            BrowserSidebarAccessPolicy.unlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: context.destination),
                in: context.browser,
                accessController: context.access
            )
        )
    }

    func testTabMoveDestinationsIncludeOnlyExactCurrentlyUnlockedAssignments() async {
        let context = makeContext(destinationIsProtected: true)
        let sourceAssignment = BrowserSpaceRuntimeAssignment(space: context.source)

        XCTAssertTrue(
            BrowserSidebarAccessPolicy.availableTabMoveDestinationSpaces(
                from: sourceAssignment,
                in: context.browser,
                accessController: context.access
            ).isEmpty
        )

        let didUnlockDestination = await context.access.unlock(context.destination)
        XCTAssertTrue(didUnlockDestination)
        XCTAssertEqual(
            BrowserSidebarAccessPolicy.availableTabMoveDestinationSpaces(
                from: sourceAssignment,
                in: context.browser,
                accessController: context.access
            ).map(\.id),
            [context.destination.id]
        )

        context.browser.session.spaces[1] = replacingProfile(
            in: context.destination,
            with: Self.uuid(9)
        )
        XCTAssertTrue(
            BrowserSidebarAccessPolicy.availableTabMoveDestinationSpaces(
                from: sourceAssignment,
                in: context.browser,
                accessController: context.access
            ).isEmpty
        )

        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.destination.id))
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }
        XCTAssertTrue(
            BrowserSidebarAccessPolicy.availableTabMoveDestinationSpaces(
                from: sourceAssignment,
                in: context.browser,
                accessController: context.access
            ).isEmpty
        )
    }

    func testPagerSettlementRequiresTheExactSelectedSpaceAndProfile() {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)

        XCTAssertTrue(
            BrowserSidebarAccessPolicy.canSettlePageSelection(
                assignment,
                settledSpaceID: context.source.id,
                in: context.browser,
                accessController: context.access
            )
        )
        XCTAssertFalse(
            BrowserSidebarAccessPolicy.canSettlePageSelection(
                assignment,
                settledSpaceID: context.destination.id,
                in: context.browser,
                accessController: context.access
            )
        )

        context.browser.session.spaces[0] = replacingProfile(
            in: context.source,
            with: Self.uuid(9)
        )
        XCTAssertFalse(
            BrowserSidebarAccessPolicy.canSettlePageSelection(
                assignment,
                settledSpaceID: context.source.id,
                in: context.browser,
                accessController: context.access
            )
        )
    }

    private func makeContext(
        sourceIsProtected: Bool = false,
        destinationIsProtected: Bool = false
    ) -> Context {
        let source = makeSpace(
            id: 1,
            profileID: 2,
            name: "Source",
            isProtected: sourceIsProtected
        )
        let destination = makeSpace(
            id: 3,
            profileID: 4,
            name: "Destination",
            isProtected: destinationIsProtected
        )
        return Context(
            browser: BrowserStore(
                session: BrowserSession(
                    spaces: [source, destination],
                    selectedSpaceID: source.id
                ),
                persistence: InMemoryBrowserSessionPersistence(),
                browsingMode: .privateBrowsing
            ),
            access: BrowserSpaceAccessController(
                authenticator: AcceptingAuthenticator()
            ),
            source: source,
            destination: destination
        )
    }

    private func makeSpace(
        id: UInt8,
        profileID: UInt8,
        name: String,
        isProtected: Bool
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(id)),
            profile: BrowsingProfile(id: Self.uuid(profileID)),
            name: name,
            symbol: "square.grid.2x2",
            accent: .indigo,
            folders: [],
            tabs: [],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open,
            selectedTabID: nil
        )
    }

    private func replacingProfile(
        in space: BrowserSpace,
        with profileID: UUID
    ) -> BrowserSpace {
        BrowserSpace(
            id: space.id,
            profile: BrowsingProfile(id: profileID),
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            branding: space.branding,
            folders: space.folders,
            tabs: space.tabs,
            archivedTabs: space.archivedTabs,
            history: space.history,
            browsingPreferences: space.browsingPreferences,
            credentialPreferences: space.credentialPreferences,
            accessPolicy: space.accessPolicy,
            isSavedTabsExpanded: space.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: space.savedTabsExpansionModifiedAt,
            selectedTabID: space.selectedTabID
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x41,
                0x43, 0x43, 0x45, 0x53, 0x53, 0x00, 0x00, finalByte
            )
        )
    }

    private struct Context {
        let browser: BrowserStore
        let access: BrowserSpaceAccessController
        let source: BrowserSpace
        let destination: BrowserSpace
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
