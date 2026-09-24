import Foundation
import XCTest

@testable import Crest

/// What Swift's session model reads back: the core's projections, which keep
/// every preference, and terms from a newer build, which resolve rather than
/// fail the whole session.
@MainActor
final class BrowserSessionRecoveryTests: XCTestCase {
    func testBehaviorPreferencesSurviveSessionRoundTrip() throws {
        var session = BrowserSession.freshInstallSeed
        var preferences = BrowserAppPreferences()
        preferences.checksSpelling = true
        preferences.automaticallyEntersPictureInPicture = false
        session.appPreferences = preferences

        let restored = try JSONDecoder().decode(
            BrowserSession.self, from: JSONEncoder().encode(session))

        XCTAssertEqual(restored.appPreferences, preferences)
    }

    // MARK: - Vocabulary tolerance

    func testASpaceAccentThisBuildHasNeverHeardOfStillDecodes() throws {
        let session = try makeSessionWithHistory()
        let data = try encoded(session) { payload in
            payload.spaces[0]["accent"] = "chartreuse"
        }

        let decoded = try JSONDecoder().decode(BrowserSession.self, from: data)

        XCTAssertEqual(decoded.spaces[0].accent, .indigo)
        XCTAssertEqual(decoded.spaces[0].name, session.spaces[0].name)
        XCTAssertEqual(
            decoded.spaces[0].tabs.map(\.id),
            session.spaces[0].tabs.map(\.id),
            "One unfamiliar tint must not cost the Space its tabs."
        )
        XCTAssertEqual(
            decoded.spaces[0].branding,
            session.spaces[0].branding,
            "Branding carries the colors that are actually drawn."
        )
    }

    func testATabPlacementThisBuildHasNeverHeardOfDecodesAsSaved() throws {
        let session = try makeSessionWithHistory()
        let tabID = session.spaces[0].tabs[0].id
        let data = try encoded(session) { payload in
            payload.spaces[0].tabs[0]["placement"] = "hibernated"
        }

        let decoded = try JSONDecoder().decode(BrowserSession.self, from: data)
        let tab = try XCTUnwrap(decoded.spaces[0].tabs.first { $0.id == tabID })

        XCTAssertEqual(
            tab.placement,
            .saved,
            "Saved keeps the address, dodges current-tab cleanup, and ignores the pin limit."
        )
        XCTAssertEqual(tab.url, session.spaces[0].tabs[0].url)
        XCTAssertEqual(decoded.spaces[0].tabs.count, session.spaces[0].tabs.count)
    }

    func testAnAccessPolicyThisBuildHasNeverHeardOfKeepsTheSpaceGuarded() throws {
        var session = try makeSessionWithHistory()
        session.spaces[0].accessPolicy = .deviceOwnerAuthentication
        let data = try encoded(session) { payload in
            payload.spaces[0]["accessPolicy"] = "hardwareKeyRequired"
        }

        let decoded = try JSONDecoder().decode(BrowserSession.self, from: data)

        XCTAssertEqual(
            decoded.spaces[0].accessPolicy,
            .deviceOwnerAuthentication,
            "Resolving an unreadable restriction to .open would unlock a private Space."
        )
    }

    func testASpaceStoringNoAccessPolicyIsStillOpen() throws {
        let session = try makeSessionWithHistory()
        let data = try encoded(session) { payload in
            payload.spaces[0]["accessPolicy"] = nil
        }

        let decoded = try JSONDecoder().decode(BrowserSession.self, from: data)

        XCTAssertEqual(
            decoded.spaces[0].accessPolicy,
            .open,
            "Sessions written before access policies existed are genuinely open."
        )
    }

    // MARK: - Helpers

    /// A mutable view of an encoded session, so a test can plant the raw term a
    /// newer build would have written without hand-authoring a whole payload.
    private struct SessionPayload {
        private var root: [String: Any]

        init(data: Data) throws {
            root = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
        }

        var spaces: SpaceList {
            get { SpaceList(raw: root["spaces"] as? [Any] ?? []) }
            set { root["spaces"] = newValue.raw }
        }

        func data() throws -> Data {
            try JSONSerialization.data(withJSONObject: root)
        }

        struct SpaceList {
            fileprivate var raw: [Any]

            subscript(index: Int) -> Space {
                get { Space(raw: raw[index] as? [String: Any] ?? [:]) }
                set { raw[index] = newValue.raw }
            }
        }

        struct Space {
            fileprivate var raw: [String: Any]

            subscript(key: String) -> Any? {
                get { raw[key] }
                set { raw[key] = newValue }
            }

            var tabs: TabList {
                get { TabList(raw: raw["tabs"] as? [Any] ?? []) }
                set { raw["tabs"] = newValue.raw }
            }
        }

        struct TabList {
            fileprivate var raw: [Any]

            subscript(index: Int) -> Tab {
                get { Tab(raw: raw[index] as? [String: Any] ?? [:]) }
                set { raw[index] = newValue.raw }
            }
        }

        struct Tab {
            fileprivate var raw: [String: Any]

            subscript(key: String) -> Any? {
                get { raw[key] }
                set { raw[key] = newValue }
            }
        }
    }

    private func encoded(
        _ session: BrowserSession,
        editing edit: (inout SessionPayload) -> Void
    ) throws -> Data {
        var payload = try SessionPayload(data: try JSONEncoder().encode(session))
        edit(&payload)
        return try payload.data()
    }

    private func makeSessionWithHistory() throws -> BrowserSession {
        var session = BrowserSession.preview
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        for spaceIndex in session.spaces.indices {
            for tabIndex in session.spaces[spaceIndex].tabs.indices {
                guard let url = session.spaces[spaceIndex].tabs[tabIndex].url else { continue }
                session.spaces[spaceIndex].tabs[tabIndex].faviconData = Data(
                    (0..<512).map { UInt8(truncatingIfNeeded: $0 &+ spaceIndex &+ tabIndex) }
                )
                session.spaces[spaceIndex].tabs[tabIndex].faviconURL = url
            }
            session.spaces[spaceIndex].history = (0..<8).map { index in
                BrowserHistoryEntry(
                    url: URL(string: "https://example.com/s\(spaceIndex)/p\(index)")!,
                    title: "Space \(spaceIndex) page \(index)",
                    firstVisitedAt: epoch,
                    lastVisitedAt: epoch.addingTimeInterval(Double(index)),
                    visitCount: index % 5 + 1
                )
            }
        }
        XCTAssertGreaterThan(session.spaces.count, 1)
        XCTAssertGreaterThan(session.spaces[0].tabs.count, 1)
        return session
    }
}
