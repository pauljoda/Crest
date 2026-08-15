import Foundation
import XCTest

@testable import Crest

/// What happens when the durable session cannot be read.
///
/// The failure this guards is total and silent: a core that will not decode used
/// to look exactly like a new installation, so the next few lines of launch seeded
/// a fresh session, saved it over the unreadable core, removed every previous
/// Space's history key, and swept every favicon that did not belong to the seed.
/// For someone without iCloud there was nothing left to recover from.
@MainActor
final class BrowserSessionRecoveryTests: XCTestCase {
    private typealias Storage = UserDefaultsBrowserSessionPersistence

    // MARK: - An unreadable core

    func testAnUnreadableV2CoreIsPreservedAndSurvivesTheFreshInstallSeedSave() async throws {
        let harness = makeHarness()
        let unreadable = Data("this is not a v2 session core".utf8)
        harness.defaults.set(unreadable, forKey: Storage.coreKey)

        XCTAssertNil(
            harness.persistence.load(),
            "An unreadable core still has no session to hand back."
        )
        XCTAssertEqual(
            harness.persistence.status,
            .preservedUnreadableSession,
            "The store must not report a new installation."
        )
        XCTAssertEqual(
            harness.persistence.preservedUnreadableSessionData(),
            unreadable,
            "The bytes have to be set aside before anything can write over them."
        )

        // Exactly what launch does next when `load()` answers nothing.
        var seed = BrowserSession.freshInstallSeed
        seed.repairRuntimeIntegrity()
        harness.persistence.save(seed)
        await harness.persistence.flushPendingSaves()

        XCTAssertEqual(
            harness.persistence.preservedUnreadableSessionData(),
            unreadable,
            "The seed save must not reach the preserved copy."
        )
        XCTAssertNotEqual(
            harness.defaults.data(forKey: Storage.coreKey),
            unreadable,
            "The live core is the seed now; the rescue is what keeps the old bytes."
        )
    }

    func testAnUnreadableCoreKeepsEveryPreviousSpacesHistory() async throws {
        let harness = makeHarness()
        let stored = try makeSessionWithHistory()
        harness.persistence.save(stored)
        await harness.persistence.flushPendingSaves()
        let historyKeys = stored.spaces.map { Storage.historyKey(for: $0.id) }
        for key in historyKeys {
            XCTAssertNotNil(harness.defaults.data(forKey: key))
        }

        harness.defaults.set(Data("truncated".utf8), forKey: Storage.coreKey)
        let relaunched = makeHarness(
            defaults: harness.defaults,
            favicons: harness.favicons
        )
        XCTAssertNil(relaunched.persistence.load())

        var seed = BrowserSession.freshInstallSeed
        seed.repairRuntimeIntegrity()
        relaunched.persistence.save(seed)
        await relaunched.persistence.flushPendingSaves()

        XCTAssertTrue(
            relaunched.recorder.removedKeys.isEmpty,
            "A session assembled without the unreadable core cannot say what is gone."
        )
        for key in historyKeys {
            XCTAssertNotNil(
                relaunched.defaults.data(forKey: key),
                "Every previous Space keeps its history while the core is unreadable."
            )
        }
    }

    func testAnUnreadableCoreSuppressesTheFaviconSweep() async throws {
        let harness = makeHarness()
        let stored = try makeSessionWithHistory()
        harness.persistence.save(stored)
        await harness.persistence.flushPendingSaves()
        let storedTabIDs = harness.favicons.storedTabIDs
        XCTAssertFalse(storedTabIDs.isEmpty)

        harness.defaults.set(Data("truncated".utf8), forKey: Storage.coreKey)
        let relaunched = makeHarness(
            defaults: harness.defaults,
            favicons: harness.favicons
        )
        XCTAssertNil(relaunched.persistence.load())

        var seed = BrowserSession.freshInstallSeed
        seed.repairRuntimeIntegrity()
        let extra = BrowserTab(
            title: "Extra",
            url: URL(string: "https://extra.example/"),
            placement: .current
        )
        seed.spaces[0].tabs.append(extra)
        relaunched.persistence.save(seed)
        await relaunched.persistence.flushPendingSaves()
        // A shrinking live-tab set is what schedules the sweep, so take the tab
        // back out. Without the guard this is the save that deletes every icon the
        // unreadable core still owns.
        seed.spaces[0].tabs.removeAll { $0.id == extra.id }
        relaunched.persistence.save(seed)
        await relaunched.persistence.flushPendingSaves()

        XCTAssertTrue(
            relaunched.favicons.pruneRequests.isEmpty,
            "No sweep may run against a session that never saw the unreadable core."
        )
        XCTAssertEqual(relaunched.favicons.storedTabIDs, storedTabIDs)
    }

    func testTheFirstPreservedCopyIsNeverReplacedByALaterOne() async throws {
        let harness = makeHarness()
        let original = Data("the session that mattered".utf8)
        harness.defaults.set(original, forKey: Storage.coreKey)
        XCTAssertNil(harness.persistence.load())

        harness.defaults.set(Data("a later, worthless core".utf8), forKey: Storage.coreKey)
        let relaunched = makeHarness(
            defaults: harness.defaults,
            favicons: harness.favicons
        )
        XCTAssertNil(relaunched.persistence.load())

        XCTAssertEqual(
            relaunched.persistence.preservedUnreadableSessionData(),
            original,
            "The earliest rescue is the one closest to the person's real session."
        )
    }

    func testDiscardingThePreservedCopyClearsIt() throws {
        let harness = makeHarness()
        harness.defaults.set(Data("unreadable".utf8), forKey: Storage.coreKey)
        XCTAssertNil(harness.persistence.load())
        XCTAssertNotNil(harness.persistence.preservedUnreadableSessionData())

        harness.persistence.discardPreservedUnreadableSession()

        XCTAssertNil(harness.persistence.preservedUnreadableSessionData())
    }

    func testAnUnreadableLegacyBlobIsPreservedAndReported() throws {
        let harness = makeHarness()
        let unreadable = Data("not a session".utf8)
        harness.defaults.set(unreadable, forKey: Storage.legacyCoreKey)

        XCTAssertNil(harness.persistence.load())

        XCTAssertEqual(harness.persistence.status, .preservedUnreadableSession)
        XCTAssertEqual(harness.persistence.preservedUnreadableSessionData(), unreadable)
        XCTAssertEqual(
            harness.defaults.data(forKey: Storage.legacyCoreKey),
            unreadable,
            "Migration never rewrites v1, so the original stays where it was too."
        )
    }

    func testAReadableSessionReportsReadyAndPreservesNothing() async throws {
        let harness = makeHarness()
        let stored = try makeSessionWithHistory()
        harness.persistence.save(stored)
        await harness.persistence.flushPendingSaves()

        let relaunched = makeHarness(
            defaults: harness.defaults,
            favicons: harness.favicons
        )
        XCTAssertEqual(relaunched.persistence.load(), stored)

        XCTAssertEqual(relaunched.persistence.status, .ready)
        XCTAssertNil(relaunched.persistence.preservedUnreadableSessionData())
    }

    func testNothingStoredIsReadyRatherThanPreserved() {
        let harness = makeHarness()

        XCTAssertNil(harness.persistence.load())

        XCTAssertEqual(
            harness.persistence.status,
            .ready,
            "A genuinely new installation is not a rescue."
        )
        XCTAssertNil(harness.persistence.preservedUnreadableSessionData())
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

    func testATabIconModeThisBuildHasNeverHeardOfFallsBackToTheTabsOwnSymbol() throws {
        var session = try makeSessionWithHistory()
        session.spaces[0].tabs[0].iconMode = .pulled
        session.spaces[0].tabs[1].symbol = BrowserTab.symbol(forEmoji: "🧭")
        session.spaces[0].tabs[1].iconMode = .emoji
        let data = try encoded(session) { payload in
            payload.spaces[0].tabs[0]["storedIconMode"] = "generated"
            payload.spaces[0].tabs[1]["storedIconMode"] = "generated"
        }

        let decoded = try JSONDecoder().decode(BrowserSession.self, from: data)

        XCTAssertEqual(
            decoded.spaces[0].tabs[0].iconMode,
            .automatic,
            "An unknown mode means 'no stored mode', which a plain tab derives as automatic."
        )
        XCTAssertEqual(
            decoded.spaces[0].tabs[1].iconMode,
            .emoji,
            "A tab wearing an emoji symbol derives emoji, exactly as a pre-modes tab does."
        )
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

    func testAV2CoreCarryingAnUnfamiliarTermLoadsInsteadOfBeingPreserved() async throws {
        let harness = makeHarness()
        let stored = try makeSessionWithHistory()
        harness.persistence.save(stored)
        await harness.persistence.flushPendingSaves()
        let core = try XCTUnwrap(harness.defaults.data(forKey: Storage.coreKey))
        var payload = try SessionPayload(data: core)
        payload.spaces[0]["accent"] = "chartreuse"
        payload.spaces[0].tabs[0]["placement"] = "hibernated"
        harness.defaults.set(try payload.data(), forKey: Storage.coreKey)

        let relaunched = makeHarness(
            defaults: harness.defaults,
            favicons: harness.favicons
        )
        let loaded = try XCTUnwrap(
            relaunched.persistence.load(),
            "A newer vocabulary is not a corrupt session."
        )

        XCTAssertEqual(relaunched.persistence.status, .ready)
        XCTAssertNil(relaunched.persistence.preservedUnreadableSessionData())
        XCTAssertEqual(loaded.spaces.map(\.id), stored.spaces.map(\.id))
        XCTAssertEqual(
            loaded.spaces[0].tabs.map(\.id),
            stored.spaces[0].tabs.map(\.id)
        )
        XCTAssertEqual(
            loaded.spaces[0].history,
            stored.spaces[0].history,
            "History survives a term the core did not recognize."
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

    private struct Harness {
        let defaults: UserDefaults
        let favicons: SpyingBrowserFaviconStore
        let recorder: BrowserSessionStorageWriteRecorder
        let persistence: UserDefaultsBrowserSessionPersistence
    }

    private func makeHarness(
        defaults: UserDefaults? = nil,
        favicons: SpyingBrowserFaviconStore? = nil
    ) -> Harness {
        let resolvedDefaults: UserDefaults
        if let defaults {
            resolvedDefaults = defaults
        } else {
            let suiteName = "BrowserSessionRecoveryTests.\(UUID().uuidString)"
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
