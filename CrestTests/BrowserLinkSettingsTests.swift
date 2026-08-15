import XCTest

@testable import Crest

@MainActor
final class BrowserLinkSettingsTests: XCTestCase {
    func testFieldLevelRouteUpdatesPreserveConcurrentValuesForTheExactRoute() throws {
        let fixture = makeFixture()
        let routeID = fixture.routeID
        let store = fixture.store

        store.updateRoute(
            routeID,
            field: .pattern("https://newer.example/reference")
        )
        store.updateRoute(
            routeID,
            field: .destinationSpaceID(fixture.secondarySpace.id)
        )

        let route = try XCTUnwrap(
            store.preferences.routes.first { $0.id == routeID }
        )
        XCTAssertEqual(route.pattern, "https://newer.example/reference")
        XCTAssertEqual(route.destinationSpaceID, fixture.secondarySpace.id)
        XCTAssertEqual(route.match, .contains)
        XCTAssertTrue(route.isEnabled)
    }

    func testFieldLevelRouteUpdateDoesNotRetargetASiblingAfterDeletion() {
        let fixture = makeFixture()
        let store = fixture.store
        let siblingID = Self.uuid(0x44)
        store.update { preferences in
            preferences.routes.append(
                BrowserLinkRoute(
                    id: siblingID,
                    match: .exact,
                    pattern: "crest-preview://links/sibling",
                    destinationSpaceID: fixture.secondarySpace.id
                )
            )
        }
        store.removeRoute(fixture.routeID)

        store.updateRoute(fixture.routeID, field: .isEnabled(false))

        XCTAssertEqual(store.preferences.routes.map(\.id), [siblingID])
        XCTAssertTrue(store.preferences.routes[0].isEnabled)
    }

    func testRoutingSkipsDeletingDestinationsBeforeChoosingARouteOrDefault() throws {
        let fixture = makeFixture()
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        var preferences = fixture.store.preferences
        preferences.routes = [
            BrowserLinkRoute(
                id: Self.uuid(0x45),
                match: .contains,
                pattern: "example.com",
                destinationSpaceID: fixture.secondarySpace.id
            ),
            BrowserLinkRoute(
                id: Self.uuid(0x46),
                match: .contains,
                pattern: "example.com",
                destinationSpaceID: fixture.primarySpace.id
            ),
        ]

        XCTAssertEqual(
            BrowserLinkRoutingPolicy.decision(
                for: url,
                preferences: preferences,
                session: fixture.session,
                unavailableSpaceIDs: [fixture.secondarySpace.id]
            ),
            .space(fixture.primarySpace.id)
        )

        preferences.routes = []
        preferences.externalLinkDestination = .chosenSpace
        preferences.externalLinkSpaceID = fixture.secondarySpace.id
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.decision(
                for: url,
                preferences: preferences,
                session: fixture.session,
                unavailableSpaceIDs: [fixture.secondarySpace.id]
            ),
            .space(fixture.primarySpace.id)
        )
    }

    func testMissingChosenSpaceDisplaysTheSelectedSpaceWithoutPersistingFallback() {
        let fixture = makeFixture()
        let missingSpaceID = SpaceID(rawValue: Self.uuid(0x77))
        let store = fixture.store
        store.update { preferences in
            preferences.externalLinkDestination = .chosenSpace
            preferences.externalLinkSpaceID = missingSpaceID
        }

        let resolved = BrowserLinkSettingsSpacePolicy.resolvedExternalSpaceID(
            preferredSpaceID: store.preferences.externalLinkSpaceID,
            spaces: fixture.session.spaces,
            selectedSpaceID: fixture.session.selectedSpaceID,
            unavailableSpaceIDs: []
        )

        XCTAssertEqual(resolved, fixture.primarySpace.id)
        XCTAssertEqual(store.preferences.externalLinkSpaceID, missingSpaceID)
    }

    private func makeFixture() -> (
        store: BrowserLinkPreferenceStore,
        session: BrowserSession,
        primarySpace: BrowserSpace,
        secondarySpace: BrowserSpace,
        routeID: UUID
    ) {
        let primarySpace = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x21)),
            profile: BrowsingProfile(id: Self.uuid(0x31)),
            name: "Primary",
            symbol: "circle.fill",
            accent: .indigo,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let secondarySpace = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x22)),
            profile: BrowsingProfile(id: Self.uuid(0x32)),
            name: "Secondary",
            symbol: "square.fill",
            accent: .orange,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let routeID = Self.uuid(0x41)
        var preferences = BrowserLinkPreferences.default
        preferences.routes = [
            BrowserLinkRoute(
                id: routeID,
                match: .contains,
                pattern: "example.com",
                destinationSpaceID: primarySpace.id
            )
        ]
        let store = BrowserLinkPreferenceStore(
            persistence: InMemoryBrowserLinkPreferencesPersistence(
                preferences: preferences
            )
        )
        let session = BrowserSession(
            spaces: [primarySpace, secondarySpace],
            selectedSpaceID: primarySpace.id
        )
        return (store, session, primarySpace, secondarySpace, routeID)
    }

    private static func uuid(_ tail: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, tail
            )
        )
    }
}
