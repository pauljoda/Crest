import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionUpdateTests: XCTestCase {
    private let darkReaderID = "eimadpbcbfnmbkopoojfekhnkhdbieeh"

    // MARK: - Cadence

    func testCadenceIsDueImmediatelyBeforeTheFirstCheck() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        for frequency in BrowserExtensionUpdateFrequency.allCases {
            XCTAssertTrue(frequency.isDue(lastCheckedAt: nil, now: now))
            XCTAssertEqual(
                frequency.timeUntilDue(lastCheckedAt: nil, now: now),
                0
            )
        }
    }

    func testWeeklyCadenceBecomesDueAfterSevenDays() {
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let frequency = BrowserExtensionUpdateFrequency.weekly

        XCTAssertFalse(
            frequency.isDue(
                lastCheckedAt: checkedAt,
                now: checkedAt.addingTimeInterval(6 * 24 * 60 * 60)
            )
        )
        XCTAssertEqual(
            frequency.timeUntilDue(
                lastCheckedAt: checkedAt,
                now: checkedAt.addingTimeInterval(6 * 24 * 60 * 60)
            ),
            24 * 60 * 60
        )
        XCTAssertTrue(
            frequency.isDue(
                lastCheckedAt: checkedAt,
                now: checkedAt.addingTimeInterval(7 * 24 * 60 * 60)
            )
        )
    }

    func testEachCadenceUsesItsOwnIntervalAndNeverReportsNegativeDelay() {
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 24 * 60 * 60
        let expected: [BrowserExtensionUpdateFrequency: TimeInterval] = [
            .daily: day,
            .weekly: 7 * day,
            .biweekly: 14 * day,
        ]

        for (frequency, interval) in expected {
            XCTAssertEqual(
                frequency.timeUntilDue(
                    lastCheckedAt: checkedAt,
                    now: checkedAt
                ),
                interval
            )
            XCTAssertTrue(
                frequency.isDue(
                    lastCheckedAt: checkedAt,
                    now: checkedAt.addingTimeInterval(interval)
                )
            )
            XCTAssertEqual(
                frequency.timeUntilDue(
                    lastCheckedAt: checkedAt,
                    now: checkedAt.addingTimeInterval(interval * 3)
                ),
                0
            )
        }
    }

    // MARK: - Version ordering

    func testVersionComparisonIsNumericRatherThanLexicographic() {
        XCTAssertEqual(
            BrowserExtensionVersionPolicy.compare("1.10", "1.9"),
            .orderedDescending
        )
        XCTAssertEqual(
            BrowserExtensionVersionPolicy.compare("4.9.129", "4.9.99"),
            .orderedDescending
        )
        XCTAssertEqual(
            BrowserExtensionVersionPolicy.compare("2.0", "2.0.0"),
            .orderedSame
        )
        XCTAssertEqual(
            BrowserExtensionVersionPolicy.compare("2.0.0.1", "2.0"),
            .orderedDescending
        )
        XCTAssertEqual(
            BrowserExtensionVersionPolicy.compare("1.2.3", "1.2.4"),
            .orderedAscending
        )
    }

    func testUnreadableVersionsAreRejectedRatherThanGuessed() {
        let unreadable = [
            "",
            "   ",
            "1.2.3.4.5",
            "1..2",
            "1.2.",
            "4.9.129 beta",
            "v1.2",
            "1.-2",
            "65536",
            "0x10",
        ]

        for version in unreadable {
            XCTAssertNil(
                BrowserExtensionVersionPolicy.compare(version, "1.0"),
                "\(version) must not compare as a Chrome version."
            )
        }
        XCTAssertEqual(
            BrowserExtensionVersionPolicy.compare("65535.65535", "65535.65534"),
            .orderedDescending
        )
    }

    func testOnlyAReadableStoreVersionCanTriggerAReplacement() {
        XCTAssertTrue(
            BrowserExtensionVersionPolicy.isUpgrade(from: "1.9", to: "1.10")
        )
        XCTAssertFalse(
            BrowserExtensionVersionPolicy.isUpgrade(from: "1.10", to: "1.9")
        )
        XCTAssertFalse(
            BrowserExtensionVersionPolicy.isUpgrade(from: "2.0", to: "2.0.0")
        )
        // An unusable local record is repaired by a well-formed store version.
        XCTAssertTrue(
            BrowserExtensionVersionPolicy.isUpgrade(from: nil, to: "1.0")
        )
        XCTAssertTrue(
            BrowserExtensionVersionPolicy.isUpgrade(
                from: "4.9.129 beta",
                to: "4.9.130"
            )
        )
        // Garbage arriving over the network never replaces a working install.
        XCTAssertFalse(
            BrowserExtensionVersionPolicy.isUpgrade(from: "1.0", to: "banana")
        )
        XCTAssertFalse(
            BrowserExtensionVersionPolicy.isUpgrade(from: nil, to: "banana")
        )
    }

    // MARK: - Endpoint

    func testDownloadEndpointKeepsItsRedirectContractOnCurrentChrome() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let query = try queryItems(
            of: BrowserChromeWebStoreUpdateRequest.url(for: id)
        )

        XCTAssertEqual(query["response"], "redirect")
        XCTAssertEqual(query["acceptformat"], "crx3")
        XCTAssertEqual(query["x"], "id=\(darkReaderID)&uc")
        XCTAssertEqual(
            query["prodversion"],
            BrowserChromeWebStoreUpdateRequest.productVersion
        )
        XCTAssertNotEqual(
            BrowserChromeWebStoreUpdateRequest.productVersion,
            "140.0.0.0",
            "The advertised Chrome build should track current stable."
        )
    }

    func testUpdateCheckEndpointAsksForTheOmahaAnswerOnTheSameHost() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let url = BrowserChromeWebStoreUpdateRequest.updateCheckURL(for: id)
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let query = try queryItems(of: url)

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "clients2.google.com")
        XCTAssertEqual(components.path, "/service/update2/crx")
        XCTAssertEqual(query["response"], "updatecheck")
        XCTAssertEqual(query["acceptformat"], "crx3")
        XCTAssertEqual(query["x"], "id=\(darkReaderID)&uc")
    }

    func testUpdateCheckEndpointCanReportAnInstalledVersion() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let query = try queryItems(
            of: BrowserChromeWebStoreUpdateRequest.updateCheckURL(
                for: id,
                installedVersion: "4.9.129"
            )
        )

        XCTAssertEqual(query["x"], "id=\(darkReaderID)&v=4.9.129&uc")
    }

    // MARK: - Omaha response parsing

    func testUpdateCheckParserReadsThePublishedVersion() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let check = try BrowserChromeWebStoreUpdateCheckParser.check(
            in: Self.availableResponse(appID: darkReaderID, version: "4.9.129"),
            expectedID: id
        )

        XCTAssertEqual(check.extensionID, id)
        XCTAssertEqual(check.publishedVersion, "4.9.129")
    }

    func testUpdateCheckParserReadsANoUpdateAnswer() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let check = try BrowserChromeWebStoreUpdateCheckParser.check(
            in: Self.noUpdateResponse(appID: darkReaderID),
            expectedID: id
        )

        XCTAssertNil(check.publishedVersion)
    }

    func testUpdateCheckParserRejectsAnAnswerForAnotherExtension() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let other = String(repeating: "a", count: 32)

        XCTAssertThrowsError(
            try BrowserChromeWebStoreUpdateCheckParser.check(
                in: Self.availableResponse(appID: other, version: "9.9.9"),
                expectedID: id
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserChromeWebStoreUpdateCheckError,
                .identityMismatch
            )
        }
    }

    func testUpdateCheckParserSurfacesADelistedExtension() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let document = """
            <?xml version="1.0" encoding="UTF-8"?>\
            <gupdate xmlns="http://www.google.com/update2/response" \
            protocol="2.0" server="prod">\
            <daystart elapsed_seconds="27873"/>\
            <app appid="\(darkReaderID)" status="error-unknownApplication"/>\
            </gupdate>
            """

        XCTAssertThrowsError(
            try BrowserChromeWebStoreUpdateCheckParser.check(
                in: Data(document.utf8),
                expectedID: id
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserChromeWebStoreUpdateCheckError,
                .applicationUnavailable("error-unknownApplication")
            )
        }
    }

    func testUpdateCheckParserRejectsUnusableDocuments() throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let unusable: [(Data, BrowserChromeWebStoreUpdateCheckError)] = [
            (Data(), .malformedDocument),
            (Data("<gupdate>".utf8), .malformedDocument),
            (
                Data(
                    """
                    <gupdate><app appid="\(darkReaderID)" status="ok">\
                    <updatecheck status="ok"/></app></gupdate>
                    """.utf8
                ),
                .malformedDocument
            ),
            (
                Data(
                    """
                    <gupdate><app appid="\(darkReaderID)" status="ok">\
                    </app></gupdate>
                    """.utf8
                ),
                .malformedDocument
            ),
            (
                Data(
                    count: BrowserChromeWebStoreUpdateCheckParser
                        .maximumResponseByteCount + 1
                ),
                .responseTooLarge
            ),
        ]

        for (data, expected) in unusable {
            XCTAssertThrowsError(
                try BrowserChromeWebStoreUpdateCheckParser.check(
                    in: data,
                    expectedID: id
                )
            ) { error in
                XCTAssertEqual(
                    error as? BrowserChromeWebStoreUpdateCheckError,
                    expected
                )
            }
        }
    }

    func testUpdateCheckerRequiresASuccessfulSecureResponse() async throws {
        let id = try XCTUnwrap(BrowserChromeExtensionID(darkReaderID))
        let payload = Self.availableResponse(
            appID: darkReaderID,
            version: "4.9.129"
        )
        let checker = BrowserChromeWebStoreUpdateChecker { url in
            (payload, Self.response(for: url, statusCode: 200))
        }

        let version = try await checker.publishedVersion(
            forExtension: id.rawValue
        )
        XCTAssertEqual(version, "4.9.129")

        let failing = BrowserChromeWebStoreUpdateChecker { url in
            (payload, Self.response(for: url, statusCode: 500))
        }
        do {
            _ = try await failing.publishedVersion(forExtension: id.rawValue)
            XCTFail("A failed response must not be parsed.")
        } catch let error as BrowserChromeWebStoreUpdateCheckError {
            XCTAssertEqual(error, .invalidResponse)
        }

        let unreachable = BrowserChromeWebStoreUpdateChecker { _ in
            throw URLError(.notConnectedToInternet)
        }
        do {
            _ = try await unreachable.publishedVersion(
                forExtension: id.rawValue
            )
            XCTFail("A transport failure must not be parsed.")
        } catch let error as BrowserChromeWebStoreUpdateCheckError {
            guard case .transport = error else {
                return XCTFail("Expected a transport failure, got \(error).")
            }
        }
    }

    func testUpdateCheckerRejectsAnIdentifierThatIsNotAChromeExtension()
        async
    {
        let checker = BrowserChromeWebStoreUpdateChecker { _ in
            XCTFail("An invalid identifier must not reach the network.")
            throw URLError(.badURL)
        }

        do {
            _ = try await checker.publishedVersion(
                forExtension: "com.example.unpacked"
            )
            XCTFail("An unpacked identifier is not a store identity.")
        } catch let error as BrowserChromeWebStoreUpdateCheckError {
            XCTAssertEqual(error, .identityMismatch)
        } catch {
            XCTFail("Unexpected error \(error).")
        }
    }

    // MARK: - Preferences

    func testPreferencesDefaultToWeeklyAutomaticUpdates() {
        XCTAssertTrue(
            BrowserExtensionUpdatePreferences.default.isAutomaticUpdateEnabled
        )
        XCTAssertEqual(
            BrowserExtensionUpdatePreferences.default.updateFrequency,
            .weekly
        )
    }

    func testPreferencesRoundTripAndToleratePartialRecords() throws {
        let preferences = BrowserExtensionUpdatePreferences(
            isAutomaticUpdateEnabled: false,
            updateFrequency: .biweekly
        )
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "crest.tests.extension-updates")
        )
        defaults.removePersistentDomain(
            forName: "crest.tests.extension-updates"
        )
        let persistence =
            UserDefaultsBrowserExtensionUpdatePreferencesPersistence(
                defaults: defaults
            )

        XCTAssertNil(persistence.load())
        persistence.save(preferences)
        XCTAssertEqual(persistence.load(), preferences)

        defaults.set(
            Data(#"{"updateFrequency":"daily"}"#.utf8),
            forKey: UserDefaultsBrowserExtensionUpdatePreferencesPersistence
                .currentKey
        )
        XCTAssertEqual(
            persistence.load(),
            BrowserExtensionUpdatePreferences(
                isAutomaticUpdateEnabled: true,
                updateFrequency: .daily
            )
        )

        persistence.reset()
        XCTAssertNil(persistence.load())
        defaults.removePersistentDomain(
            forName: "crest.tests.extension-updates"
        )
    }

    // MARK: - Scheduling

    func testDisabledAutomaticUpdatesNeverScheduleAPass() async {
        let environment = makeEnvironment(
            preferences: BrowserExtensionUpdatePreferences(
                isAutomaticUpdateEnabled: false,
                updateFrequency: .daily
            ),
            targets: [Self.target(version: "1.0")],
            publishedVersion: "2.0"
        )

        environment.model.scheduleCheckIfNeeded()
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(environment.sleeper.invocationCount, 0)
        XCTAssertEqual(environment.checker.requestCount, 0)
        XCTAssertTrue(environment.applier.appliedTargetIDs.isEmpty)
        XCTAssertNil(environment.model.lastCheckedAt)
    }

    func testDueScheduleUpdatesOnlyTheExtensionsWithANewerVersion() async {
        let environment = makeEnvironment(
            targets: [
                Self.target(extensionID: Self.identifier(1), version: "1.0"),
                Self.target(extensionID: Self.identifier(2), version: "2.0"),
            ],
            publishedVersion: "2.0"
        )

        environment.model.scheduleCheckIfNeeded()
        await environment.settle()

        XCTAssertEqual(environment.checker.requestCount, 2)
        XCTAssertEqual(
            environment.applier.appliedExtensionIDs,
            [Self.identifier(1)]
        )
        XCTAssertEqual(environment.model.lastCheckedAt, Self.checkDate)
        XCTAssertEqual(environment.model.updateRevision, 1)
        XCTAssertNil(environment.model.lastErrorDescription)
        XCTAssertEqual(
            environment.metadata.loadLastCheckedAt(),
            Self.checkDate
        )
    }

    func testManualCheckIsOfferedOnlyWhenSomethingCouldBeUpdated() {
        XCTAssertFalse(
            makeEnvironment(targets: []).model.hasUpdatableExtensions
        )
        XCTAssertFalse(
            makeEnvironment(
                targets: [Self.target(version: "1.0", isEnabled: false)]
            ).model.hasUpdatableExtensions
        )
        XCTAssertTrue(
            makeEnvironment(
                targets: [Self.target(version: "1.0")]
            ).model.hasUpdatableExtensions
        )
    }

    func testDisabledInstallationsAreLeftAloneByAnUpdatePass() async {
        let environment = makeEnvironment(
            targets: [
                Self.target(
                    extensionID: Self.identifier(1),
                    version: "1.0",
                    isEnabled: false
                ),
                Self.target(extensionID: Self.identifier(2), version: "1.0"),
            ],
            publishedVersion: "2.0"
        )

        await environment.model.checkForUpdatesNow()

        XCTAssertEqual(environment.checker.requestCount, 1)
        XCTAssertEqual(
            environment.applier.appliedExtensionIDs,
            [Self.identifier(2)]
        )
    }

    func testCheckNowRunsEvenWhenAutomaticUpdatesAreOff() async {
        let environment = makeEnvironment(
            preferences: BrowserExtensionUpdatePreferences(
                isAutomaticUpdateEnabled: false,
                updateFrequency: .weekly
            ),
            lastCheckedAt: Self.checkDate,
            targets: [Self.target(version: "1.0")],
            publishedVersion: "2.0"
        )

        await environment.model.checkForUpdatesNow()
        await environment.drainScheduling()

        XCTAssertEqual(environment.applier.appliedExtensionIDs.count, 1)
        XCTAssertEqual(environment.model.lastCheckedAt, Self.checkDate)
        // A forced pass must not arm a cadence the toggle says is off.
        XCTAssertEqual(environment.sleeper.invocationCount, 0)
    }

    func testAPassWhereEveryExtensionFailsRetriesSoon() async {
        let environment = makeEnvironment(
            targets: [Self.target(version: "1.0")],
            checkFailure: URLError(.notConnectedToInternet)
        )

        await environment.model.checkForUpdatesNow()
        await environment.drainScheduling()

        XCTAssertNotNil(environment.model.lastErrorDescription)
        XCTAssertEqual(environment.model.updateRevision, 0)
        XCTAssertEqual(environment.sleeper.invocationCount, 1)
        XCTAssertEqual(
            environment.sleeper.requestedDelays.first,
            .seconds(60 * 60)
        )
    }

    func testOneUnhappyExtensionDoesNotWedgeTheOrdinaryCadence() async {
        let environment = makeEnvironment(
            targets: [
                Self.target(extensionID: Self.identifier(1), version: "1.0"),
                Self.target(extensionID: Self.identifier(2), version: "1.0"),
            ],
            publishedVersion: "2.0"
        )
        environment.checker.failingExtensionIDs = [Self.identifier(1)]

        await environment.model.checkForUpdatesNow()
        await environment.drainScheduling()

        XCTAssertEqual(
            environment.applier.appliedExtensionIDs,
            [Self.identifier(2)]
        )
        XCTAssertNotNil(environment.model.lastErrorDescription)
        XCTAssertEqual(environment.model.lastCheckedAt, Self.checkDate)
        XCTAssertEqual(environment.sleeper.invocationCount, 1)
        XCTAssertEqual(
            environment.sleeper.requestedDelays.first,
            .seconds(7 * 24 * 60 * 60)
        )
    }

    func testSwitchingAutomaticUpdatesOffCancelsAnArmedSchedule() async {
        let environment = makeEnvironment(
            lastCheckedAt: Self.checkDate,
            targets: [Self.target(version: "1.0")],
            publishedVersion: "2.0"
        )

        environment.model.scheduleCheckIfNeeded()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(environment.sleeper.invocationCount, 1)

        environment.model.setAutomaticUpdateEnabled(false)
        for _ in 0..<50 { await Task.yield() }

        XCTAssertFalse(
            environment.model.preferences.isAutomaticUpdateEnabled
        )
        XCTAssertEqual(environment.checker.requestCount, 0)
        XCTAssertTrue(environment.applier.appliedExtensionIDs.isEmpty)
    }

    func testChangingFrequencyRearmsTheScheduleWithTheNewInterval() async {
        let environment = makeEnvironment(
            preferences: BrowserExtensionUpdatePreferences(
                isAutomaticUpdateEnabled: true,
                updateFrequency: .biweekly
            ),
            lastCheckedAt: Self.checkDate,
            targets: [Self.target(version: "1.0")],
            publishedVersion: "2.0"
        )

        environment.model.scheduleCheckIfNeeded()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(
            environment.sleeper.requestedDelays,
            [.seconds(14 * 24 * 60 * 60)]
        )

        environment.model.setUpdateFrequency(.daily)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(
            environment.sleeper.requestedDelays,
            [.seconds(14 * 24 * 60 * 60), .seconds(24 * 60 * 60)]
        )
        XCTAssertEqual(
            environment.preferences.load()?.updateFrequency,
            .daily
        )
    }

    func testAPassWithNoStoreSourcedExtensionsStillStampsTheCheck() async {
        let environment = makeEnvironment(targets: [])

        environment.model.scheduleCheckIfNeeded()
        await environment.settle()

        XCTAssertEqual(environment.checker.requestCount, 0)
        XCTAssertEqual(environment.model.lastCheckedAt, Self.checkDate)
        XCTAssertEqual(environment.model.updateRevision, 0)
    }

    // MARK: - Environment

    private final class RecordingExtensionUpdateChecker:
        BrowserExtensionUpdateChecking,
        @unchecked Sendable
    {
        private let lock = NSLock()
        private let offeredVersion: String?
        private let failure: (any Error)?
        private var requests: [String] = []
        private var failingIDs: Set<String> = []

        init(publishedVersion: String?, failure: (any Error)?) {
            offeredVersion = publishedVersion
            self.failure = failure
        }

        var requestCount: Int {
            lock.withLock { requests.count }
        }

        var failingExtensionIDs: Set<String> {
            get { lock.withLock { failingIDs } }
            set { lock.withLock { failingIDs = newValue } }
        }

        func publishedVersion(
            forExtension extensionID: String
        ) async throws -> String? {
            lock.withLock { requests.append(extensionID) }
            if let failure { throw failure }
            guard !failingExtensionIDs.contains(extensionID) else {
                throw URLError(.timedOut)
            }
            return offeredVersion
        }
    }

    @MainActor
    private final class RecordingExtensionUpdateApplier:
        BrowserExtensionUpdateApplying
    {
        private let targets: [BrowserExtensionUpdateTarget]
        private(set) var appliedTargetIDs: [String] = []
        private(set) var appliedExtensionIDs: [String] = []

        init(targets: [BrowserExtensionUpdateTarget]) {
            self.targets = targets
        }

        func chromeWebStoreUpdateTargets() -> [BrowserExtensionUpdateTarget] {
            targets
        }

        func applyUpdate(
            to target: BrowserExtensionUpdateTarget
        ) async throws -> String? {
            appliedTargetIDs.append(target.id)
            appliedExtensionIDs.append(target.extensionID)
            return nil
        }
    }

    /// Records what the scheduler asked to wait for and then abandons the
    /// scheduled task, so a test can assert the cadence was armed without
    /// letting an armed pass actually fire.
    private final class RecordingExtensionUpdateSleeper: @unchecked Sendable {
        private let lock = NSLock()
        private var delays: [Duration] = []

        var requestedDelays: [Duration] {
            lock.withLock { delays }
        }

        var invocationCount: Int {
            lock.withLock { delays.count }
        }

        func sleep(for duration: Duration) async throws {
            lock.withLock { delays.append(duration) }
            throw CancellationError()
        }
    }

    @MainActor
    private struct Environment {
        let model: BrowserExtensionUpdateModel
        let checker: RecordingExtensionUpdateChecker
        let applier: RecordingExtensionUpdateApplier
        let sleeper: RecordingExtensionUpdateSleeper
        let preferences: InMemoryBrowserExtensionUpdatePreferencesPersistence
        let metadata: InMemoryBrowserExtensionUpdateMetadataPersistence

        func settle() async {
            for _ in 0..<200 {
                if !model.isChecking, model.lastCheckedAt != nil { break }
                await Task.yield()
            }
            await drainScheduling()
        }

        /// Lets the follow-up task a finished pass just created reach its
        /// first suspension, so the armed cadence is observable.
        func drainScheduling() async {
            for _ in 0..<50 { await Task.yield() }
        }
    }

    private func makeEnvironment(
        preferences: BrowserExtensionUpdatePreferences = .default,
        lastCheckedAt: Date? = nil,
        targets: [BrowserExtensionUpdateTarget],
        publishedVersion: String? = nil,
        checkFailure: (any Error)? = nil
    ) -> Environment {
        let preferencesPersistence =
            InMemoryBrowserExtensionUpdatePreferencesPersistence(
                preferences: preferences
            )
        let metadata = InMemoryBrowserExtensionUpdateMetadataPersistence(
            lastCheckedAt: lastCheckedAt
        )
        let checker = RecordingExtensionUpdateChecker(
            publishedVersion: publishedVersion,
            failure: checkFailure
        )
        let applier = RecordingExtensionUpdateApplier(targets: targets)
        let sleeper = RecordingExtensionUpdateSleeper()
        let model = BrowserExtensionUpdateModel(
            preferencesPersistence: preferencesPersistence,
            updateMetadataPersistence: metadata,
            checker: checker,
            applier: applier,
            now: { Self.checkDate },
            sleep: sleeper.sleep
        )
        return Environment(
            model: model,
            checker: checker,
            applier: applier,
            sleeper: sleeper,
            preferences: preferencesPersistence,
            metadata: metadata
        )
    }

    private func queryItems(of url: URL) throws -> [String: String] {
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        return Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }
        )
    }

    nonisolated private static let checkDate = Date(
        timeIntervalSince1970: 1_700_000_000
    )

    private static let spaceID = SpaceID(
        rawValue: UUID(
            uuid: (
                0x51, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
            )
        )
    )

    private static func identifier(_ index: Int) -> String {
        String(repeating: "abcdefgh", count: 3)
            + String(repeating: "abcdefg", count: 1)
            + String(UnicodeScalar(UInt8(0x61 + index)))
    }

    private static func target(
        extensionID: String = BrowserExtensionUpdateTests.identifier(0),
        version: String?,
        isEnabled: Bool = true
    ) -> BrowserExtensionUpdateTarget {
        BrowserExtensionUpdateTarget(
            extensionID: extensionID,
            spaceID: spaceID,
            displayName: "Probe \(extensionID.suffix(1))",
            installedVersion: version,
            isEnabled: isEnabled
        )
    }

    private static func availableResponse(
        appID: String,
        version: String
    ) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>\
            <gupdate xmlns="http://www.google.com/update2/response" \
            protocol="2.0" server="prod">\
            <daystart elapsed_days="7164" elapsed_seconds="27873"/>\
            <app appid="\(appID)" cohort="1::" cohortname="" status="ok">\
            <updatecheck _esbAllowlist="true" \
            codebase="https://clients2.googleusercontent.com/crx/blobs/probe.crx" \
            fp="1.abc" hash_sha256="abc" protected="0" size="839237" \
            status="ok" version="\(version)"/>\
            </app></gupdate>
            """.utf8
        )
    }

    private static func noUpdateResponse(appID: String) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>\
            <gupdate xmlns="http://www.google.com/update2/response" \
            protocol="2.0" server="prod">\
            <daystart elapsed_days="7164" elapsed_seconds="27882"/>\
            <app appid="\(appID)" cohort="1::" cohortname="" status="ok">\
            <updatecheck _esbAllowlist="true" status="noupdate"/>\
            </app></gupdate>
            """.utf8
        )
    }

    nonisolated private static func response(
        for url: URL,
        statusCode: Int
    ) -> URLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }
}
