import XCTest

@testable import Crest

@MainActor
final class BrowserLinkSettingsTests: XCTestCase {
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

    /// The defaults keep every Space the preferences name in the spelling
    /// earlier builds read, and a bare identity reads back the same.
    func testPreferencesKeepTheStoredSpaceSpellingAndReadABareOne() throws {
        let suiteName = "crest.link-preferences-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserLinkPreferencesPersistence(defaults: defaults)
        let chosen = SpaceID()
        let routed = SpaceID()
        let remembered = SpaceID()
        var preferences = BrowserLinkPreferences.default
        preferences.externalLinkDestination = .chosenSpace
        preferences.externalLinkSpaceID = chosen
        preferences.routes = [BrowserLinkRoute(pattern: "example.com", destinationSpaceID: routed)]
        preferences.rememberedQuickWindowSpacesBySite = ["example.com": remembered]

        persistence.save(preferences)
        let data = try XCTUnwrap(defaults.data(forKey: UserDefaultsBrowserLinkPreferencesPersistence.currentKey))
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(stored["externalLinkSpaceID"] as? [String: String], StoredIdentityJSON.wrapped(chosen))
        let route = try XCTUnwrap((stored["routes"] as? [[String: Any]])?.first)
        XCTAssertEqual(route["destinationSpaceID"] as? [String: String], StoredIdentityJSON.wrapped(routed))
        XCTAssertEqual(
            stored["rememberedQuickWindowSpacesBySite"] as? [String: [String: String]],
            ["example.com": StoredIdentityJSON.wrapped(remembered)])
        XCTAssertEqual(persistence.load(), preferences)

        defaults.set(
            try JSONSerialization.data(withJSONObject: StoredIdentityJSON.bare(stored)),
            forKey: UserDefaultsBrowserLinkPreferencesPersistence.currentKey)
        XCTAssertEqual(persistence.load(), preferences)
    }

    private func makeFixture() -> (
        store: BrowserLinkPreferenceStore,
        session: BrowserSession,
        primarySpace: BrowserSpace,
        secondarySpace: BrowserSpace,
        routeID: UUID
    ) {
        let primarySpace = BrowserSpace(
            id: Self.uuid(0x21),
            profile: BrowsingProfile(id: Self.uuid(0x31)),
            name: "Primary",
            symbol: "circle.fill",
            accent: .indigo,
            folders: [],
            tabs: []
        )
        let secondarySpace = BrowserSpace(
            id: Self.uuid(0x22),
            profile: BrowsingProfile(id: Self.uuid(0x32)),
            name: "Secondary",
            symbol: "square.fill",
            accent: .orange,
            folders: [],
            tabs: []
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
        let session = BrowserSession(spaces: [primarySpace, secondarySpace])
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
