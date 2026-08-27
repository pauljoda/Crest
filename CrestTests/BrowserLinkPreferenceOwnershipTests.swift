import XCTest

@testable import Crest

@MainActor
final class BrowserLinkPreferenceOwnershipTests: XCTestCase {
    func testUserDefaultsPersistenceRoundTripsTheCurrentPayloadUnderTheStableKey() throws {
        let context = try makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let destinationSpaceID = SpaceID()
        let routeID = try XCTUnwrap(
            UUID(uuidString: "B41B75B7-B552-4BD7-B9A8-50E768D39D94")
        )
        let preferences = BrowserLinkPreferences(
            externalLinkDestination: .chosenSpace,
            externalLinkSpaceID: destinationSpaceID,
            focusesNewTabsOpenedFromLinks: true,
            automaticallyOpensPeek: false,
            peekClickModifier: .command,
            quickWindowArchivePolicy: .after24Hours,
            remembersQuickWindowSpaceBySite: false,
            routes: [
                BrowserLinkRoute(
                    id: routeID,
                    match: .exact,
                    pattern: "https://example.com/reference",
                    destinationSpaceID: destinationSpaceID
                )
            ],
            rememberedQuickWindowSpacesBySite: ["example.com": destinationSpaceID]
        )
        let persistence = UserDefaultsBrowserLinkPreferencesPersistence(
            defaults: context.defaults
        )

        persistence.save(preferences)

        let encoded = try XCTUnwrap(
            context.defaults.data(forKey: "crest.link-preferences.v1")
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(
            Set(payload.keys),
            [
                "externalLinkDestination",
                "externalLinkSpaceID",
                "focusesNewTabsOpenedFromLinks",
                "automaticallyOpensPeek",
                "peekClickModifier",
                "quickWindowArchivePolicy",
                "remembersQuickWindowSpaceBySite",
                "routes",
                "rememberedQuickWindowSpacesBySite",
            ]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(BrowserLinkPreferences.self, from: encoded),
            preferences
        )
        XCTAssertEqual(persistence.load(), preferences)
    }

    func testUserDefaultsPersistenceMigratesTheLegacyPayloadMissingCurrentKeys() throws {
        let context = try makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let persistence = UserDefaultsBrowserLinkPreferencesPersistence(
            defaults: context.defaults
        )
        context.defaults.set(
            Data(
                #"{"externalLinkDestination":"mostRecentSpace","automaticallyOpensPeek":false}"#
                    .utf8
            ),
            forKey: "crest.link-preferences.v1"
        )

        let restored = try XCTUnwrap(persistence.load())

        XCTAssertEqual(restored.externalLinkDestination, .mostRecentSpace)
        XCTAssertFalse(restored.focusesNewTabsOpenedFromLinks)
        XCTAssertFalse(restored.automaticallyOpensPeek)
        XCTAssertEqual(restored.peekClickModifier, .option)
        XCTAssertEqual(restored.quickWindowArchivePolicy, .after6Hours)
        XCTAssertTrue(restored.remembersQuickWindowSpaceBySite)
        XCTAssertEqual(restored.routes, [])
        XCTAssertEqual(restored.rememberedQuickWindowSpacesBySite, [:])
    }

    func testStoreMutationsPersistThroughThePortAndResetRemovesThePayload() {
        let destinationSpaceID = SpaceID()
        let persistence = RecordingBrowserLinkPreferencesPersistence()
        let store = BrowserLinkPreferenceStore(persistence: persistence)

        store.update { $0.externalLinkDestination = .chosenSpace }
        store.addRoute(destinationSpaceID: destinationSpaceID)
        let routeID = store.preferences.routes[0].id
        store.moveRoute(routeID, by: 1)

        XCTAssertEqual(persistence.savedPreferences.count, 2)
        XCTAssertEqual(persistence.savedPreferences.last, store.preferences)

        store.reset()

        XCTAssertEqual(store.preferences, .default)
        XCTAssertEqual(persistence.removeCallCount, 1)
    }

    func testRoutingPolicyMatchesNormalizedExactAndContainsRoutesInOrder() throws {
        let session = BrowserSession.preview
        let firstSpaceID = try XCTUnwrap(session.spaces.first?.id)
        let lastSpaceID = try XCTUnwrap(session.spaces.last?.id)
        var preferences = BrowserLinkPreferences.default
        preferences.routes = [
            BrowserLinkRoute(
                isEnabled: false,
                match: .contains,
                pattern: "EXAMPLE.COM",
                destinationSpaceID: lastSpaceID
            ),
            BrowserLinkRoute(
                match: .contains,
                pattern: "example.com",
                destinationSpaceID: SpaceID()
            ),
            BrowserLinkRoute(
                match: .exact,
                pattern: "https://example.com/reference#configured-fragment",
                destinationSpaceID: firstSpaceID
            ),
            BrowserLinkRoute(
                match: .contains,
                pattern: "example.com",
                destinationSpaceID: lastSpaceID
            ),
        ]
        let exactURL = try XCTUnwrap(
            URL(string: "https://EXAMPLE.com/reference#visited-fragment")
        )
        let containedURL = try XCTUnwrap(URL(string: "https://example.com/another"))

        XCTAssertEqual(
            BrowserLinkRoutingPolicy.decision(
                for: exactURL,
                preferences: preferences,
                session: session
            ),
            .space(firstSpaceID)
        )
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.decision(
                for: containedURL,
                preferences: preferences,
                session: session
            ),
            .space(lastSpaceID)
        )
    }

    func testRoutingPolicyFallsBackFromSpacesOutsideTheCurrentSession() throws {
        let session = BrowserSession.preview
        let selectedSpaceID = session.selectedSpaceID
        let unavailableSpaceID = SpaceID()
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        var preferences = BrowserLinkPreferences.default
        preferences.rememberedQuickWindowSpacesBySite = [
            "example.com": unavailableSpaceID
        ]

        XCTAssertEqual(
            BrowserLinkRoutingPolicy.decision(
                for: url,
                preferences: preferences,
                session: session
            ),
            .quickWindow(spaceID: selectedSpaceID)
        )

        preferences.externalLinkDestination = .chosenSpace
        preferences.externalLinkSpaceID = unavailableSpaceID
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.decision(
                for: url,
                preferences: preferences,
                session: session
            ),
            .space(selectedSpaceID)
        )
    }

    private func makeDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "BrowserLinkPreferenceOwnershipTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}

private final class RecordingBrowserLinkPreferencesPersistence:
    BrowserLinkPreferencesPersisting
{
    private(set) var savedPreferences: [BrowserLinkPreferences] = []
    private(set) var removeCallCount = 0

    func load() -> BrowserLinkPreferences? {
        nil
    }

    func save(_ preferences: BrowserLinkPreferences) {
        savedPreferences.append(preferences)
    }

    func remove() {
        removeCallCount += 1
    }
}
