import CloudKit
import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCloudSyncControllerTests: XCTestCase {
    func testUnconfiguredControllerReportsTheExistingFailureAndDiagnostics() async throws {
        let suiteName = "BrowserCloudSyncControllerTests.Unconfigured.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: nil,
            defaults: defaults
        )

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(controller.phase, .checking)
        XCTAssertEqual(controller.accountState, .checking)
        XCTAssertNil(controller.containerIdentifier)

        await controller.start()

        XCTAssertEqual(
            controller.phase,
            .failed("Crest’s CloudKit container is not configured.")
        )
        XCTAssertEqual(controller.accountState, .couldNotDetermine)
        XCTAssertNil(controller.errorDescription)
        XCTAssertTrue(controller.diagnosticsReport.contains("Container: Not configured"))
        XCTAssertTrue(controller.diagnosticsReport.contains("Enabled: true"))
        XCTAssertTrue(controller.diagnosticsReport.contains("Account: Could not determine"))
        XCTAssertTrue(controller.diagnosticsReport.contains("Status: Needs attention"))
    }

    func testAvailableAccountStartsAutomaticTransportWithoutForcingAManualSync() async throws {
        let core = CrestCore()
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .available)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )

        await controller.start()

        XCTAssertEqual(controller.accountState, .available)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertNotNil(controller.lastAttemptAt)
        XCTAssertNil(controller.lastSuccessAt)
        let transport = try XCTUnwrap(factory.transports.first)
        let startCount = await transport.startCount
        let syncCount = await transport.syncCount
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(syncCount, 0)

        await transport.emit(.fetched(recordCount: 4))
        await transport.emit(.uploaded(recordCount: 3))
        await controller.localChangesDidStage()

        XCTAssertEqual(controller.lastFetchedRecordCount, 4)
        XCTAssertEqual(controller.lastUploadedRecordCount, 3)
        XCTAssertNotNil(controller.lastSuccessAt)
        let notifyCount = await transport.notifyCount
        XCTAssertEqual(notifyCount, 1)
    }

    /// A core that cannot answer for this device's journal stops the start
    /// before anything reaches iCloud: its refusal never reads as a device
    /// with nothing to keep, which would take the cloud's content instead.
    func testAComparisonTheCoreRefusesStopsSyncWithoutTakingTheCloud() async throws {
        let preferences = TestBrowserCloudSyncPreferences(requiresAccountConfirmation: true)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: TestBrowserCloudSyncRemoteService(
                accountState: .available, snapshot: try cloudRecords(of: .privateBrowsing())),
            transportFactory: factory
        )

        await controller.start()

        guard case .failed = controller.phase else { return XCTFail("Sync started over a refused comparison.") }
        XCTAssertTrue(factory.transports.isEmpty)
        XCTAssertNil(controller.conflict)
        XCTAssertEqual(preferences.resetCount, 0)
    }

    func testUnavailableAccountWaitsWithoutCreatingATransport() async {
        let core = CrestCore()
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .noAccount)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )

        await controller.start()

        XCTAssertEqual(controller.accountState, .noAccount)
        XCTAssertEqual(controller.phase, .waitingForAccount)
        XCTAssertTrue(factory.transports.isEmpty)
    }

    func testDifferentAccountContentPausesForExplicitReconciliation() async throws {
        let device = try await syncedDevice()
        let local = try device.storedJournal()
        let cloud = try cloudRecords(of: .privateBrowsing())
        let preferences = TestBrowserCloudSyncPreferences(
            requiresAccountConfirmation: true
        )
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: cloud
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )

        await controller.start()

        XCTAssertEqual(controller.phase, .needsReconciliation)
        XCTAssertEqual(
            controller.conflict,
            BrowserCloudSyncConflictSummary(
                localRecordCount: local.records.count,
                cloudRecordCount: cloud.count,
                localSpaceCount: BrowserSession.preview.spaces.count,
                cloudSpaceCount: 1
            )
        )
        XCTAssertEqual(controller.observedCloudRecordCount, cloud.count)
        XCTAssertTrue(factory.transports.isEmpty)
        XCTAssertEqual(try device.storedJournal(), local, "Neither copy is replaced or overwritten")
    }

    func testUseICloudResolutionReplacesLocalContentAndClearsThePause() async throws {
        let device = try await syncedDevice()
        let cloudSession = BrowserSession.privateBrowsing()
        let preferences = TestBrowserCloudSyncPreferences(
            requiresAccountConfirmation: true
        )
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: try cloudRecords(of: cloudSession)
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        await controller.start()

        await controller.resolveUsingICloud()

        XCTAssertEqual(device.store.session.spaces.map(\.id), cloudSession.spaces.map(\.id))
        XCTAssertTrue(try device.core.query(PendingUploads()).records.isEmpty)
        XCTAssertEqual(preferences.savedConflictResolutions.count, 1)
        XCTAssertNil(preferences.savedConflictResolutions[0])
        XCTAssertNil(controller.conflict)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testUseThisDeviceResolutionStagesAnOverwriteAndPersistsTheChoice() async throws {
        let device = try await syncedDevice()
        let local = device.store.session
        let preferences = TestBrowserCloudSyncPreferences(
            requiresAccountConfirmation: true
        )
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: try cloudRecords(of: .privateBrowsing())
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        await controller.start()

        await controller.resolveUsingThisDevice()

        XCTAssertEqual(device.store.session, local)
        let journal = try device.storedJournal()
        XCTAssertEqual(journal.pendingRecordIDs, Set(journal.records.map(\.id)))
        XCTAssertEqual(preferences.savedConflictResolutions, [.useThisDevice])
        XCTAssertNil(controller.conflict)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testDisposableSeedIsReplacedBeforeTransportStarts() async throws {
        let device = try await syncedDevice(.freshInstallSeed)
        let cloudSession = BrowserSession.privateBrowsing()
        let cloud = try cloudRecords(of: cloudSession)
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: cloud
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        XCTAssertTrue(device.core.state.syncsDisposableSeed)

        await controller.start()

        XCTAssertFalse(device.core.state.syncsDisposableSeed)
        XCTAssertEqual(device.store.session.spaces.map(\.id), cloudSession.spaces.map(\.id))
        XCTAssertEqual(preferences.resetCount, 1)
        XCTAssertEqual(controller.observedCloudRecordCount, cloud.count)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testAccountChangeDiscardsTheTransportAndRestartsAgainstTheCurrentAccount() async throws {
        let core = CrestCore()
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .available)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        await controller.start()
        let firstTransport = try XCTUnwrap(factory.transports.first)

        await firstTransport.emit(.accountChanged)
        for _ in 0..<100
        where factory.transports.count < 2 || controller.phase != .ready {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(factory.transports.count, 2)
        XCTAssertEqual(controller.accountState, .available)
        XCTAssertEqual(controller.phase, .ready)
    }

    /// Turning sync off must not launder the wrong-account guard. Clearing the
    /// stored pause here would let the next switch on merge this device's Spaces
    /// into whichever account is signed in, without asking again.
    func testTurningSyncOffKeepsAPendingAccountDecision() async throws {
        let preferences = TestBrowserCloudSyncPreferences(
            requiresAccountConfirmation: true
        )
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available),
            transportFactory: TestBrowserCloudSyncTransportFactory()
        )

        controller.isEnabled = false
        for _ in 0..<100 where controller.phase != .disabled {
            await Task.yield()
        }

        XCTAssertEqual(controller.phase, .disabled)
        XCTAssertEqual(preferences.resetCount, 0)
        XCTAssertTrue(try preferences.requiresAccountConfirmation())
    }

    /// A disable that lands while `start` is suspended used to be overtaken: the
    /// resumed launch built a transport with automatic sync on and reported Ready
    /// while the interface said Off.
    func testDisablingSyncMidLaunchLeavesNoLiveTransport() async throws {
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            suspendsAccountState: true
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: remote,
            transportFactory: factory
        )
        let launch = Task { await controller.start() }
        for _ in 0..<200 where !(await remote.isSuspendedForTesting) {
            await Task.yield()
        }

        controller.isEnabled = false
        await remote.release()
        await launch.value
        for _ in 0..<100 where controller.phase != .disabled {
            await Task.yield()
        }

        XCTAssertTrue(factory.transports.isEmpty)
        XCTAssertEqual(controller.phase, .disabled)
        XCTAssertNil(controller.lastSuccessAt)
    }

    /// A failure raised while handling a fetched batch must not be painted over
    /// with "Up to date" in the same cycle.
    func testAFailedSyncIsNeverReportedAsUpToDate() async throws {
        let factory = TestBrowserCloudSyncTransportFactory(
            syncFailure: TestBrowserCloudSyncRemoteService.TestFailure.unavailable
        )
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available),
            transportFactory: factory
        )

        await controller.start()
        await controller.syncNow()

        XCTAssertNil(controller.lastSuccessAt)
        XCTAssertNotEqual(controller.phase, .ready)
        XCTAssertNotNil(controller.errorDescription)
    }

    func testAnExistingTransportFailureIsNotRetriedByTheController() async throws {
        let factory = TestBrowserCloudSyncTransportFactory(
            syncFailure: TestBrowserCloudSyncRemoteService.TestFailure.unavailable
        )
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available),
            transportFactory: factory,
            retryDelay: .milliseconds(1)
        )
        await controller.start()
        let transport = try XCTUnwrap(factory.transports.first)

        await controller.syncNow()
        try? await Task.sleep(for: .milliseconds(30))

        let syncCount = await transport.syncCount
        XCTAssertEqual(syncCount, 1)
        XCTAssertNotEqual(controller.phase, .ready)
    }

    func testAutomaticActivityClearsARecoveredTransientFailure() async throws {
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available),
            transportFactory: factory
        )
        await controller.start()
        let transport = try XCTUnwrap(factory.transports.first)
        await transport.emit(.failed("iCloud is temporarily unavailable."))

        await transport.emit(.uploaded(recordCount: 2))

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertNil(controller.errorDescription)
        XCTAssertEqual(controller.lastUploadedRecordCount, 2)
        XCTAssertNotNil(controller.lastSuccessAt)
    }

    func testSkippedRecordsAndRemovedCloudDataReachTheDiagnostics() async throws {
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available),
            transportFactory: factory
        )
        await controller.start()
        let transport = try XCTUnwrap(factory.transports.first)

        await transport.emit(.skippedRecords(count: 2, requiresAppUpdate: true))
        await transport.emit(.cloudDataRemoved)

        XCTAssertEqual(controller.skippedRecordCount, 2)
        XCTAssertTrue(controller.requiresAppUpdate)
        XCTAssertTrue(controller.cloudDataWasRemoved)
        XCTAssertTrue(controller.diagnosticsReport.contains("Records skipped: 2"))
        XCTAssertTrue(controller.diagnosticsReport.contains("Needs app update: true"))
        XCTAssertTrue(controller.diagnosticsReport.contains("iCloud data removed: true"))
    }

    /// Nothing observed `CKAccountChanged`, so a device that was signed out at
    /// launch stayed dormant until the next launch or a manual Sync Now.
    func testAnAccountChangeNotificationRestartsSyncOnItsOwn() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("BrowserCloudSyncControllerTests.accountChanged")
        let factory = TestBrowserCloudSyncTransportFactory()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .noAccount)
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: remote,
            transportFactory: factory,
            retryDelay: .seconds(600)
        )
        controller.observeAccountChanges(named: name, center: center)
        await controller.start()
        XCTAssertEqual(controller.phase, .waitingForAccount)
        XCTAssertTrue(factory.transports.isEmpty)

        await remote.signIn()
        center.post(name: name, object: nil)
        for _ in 0..<300 where controller.phase != .ready {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testATransientLaunchFailureRetriesWithoutAnotherLaunch() async throws {
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            initialFailures: 1
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: remote,
            transportFactory: factory,
            retryDelay: .milliseconds(1)
        )

        await controller.start()
        XCTAssertNotEqual(controller.phase, .ready)

        for _ in 0..<300 where controller.phase != .ready {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testPullUsesFreshSnapshotTransportAndReportsItsCount() async throws {
        let device = try await syncedDevice()
        let local = device.store.session
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core, configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available),
            transportFactory: factory
        )
        await controller.start()
        await controller.pullFromICloud()

        let transport = try XCTUnwrap(factory.transports.first)
        let pulls = await transport.pullCount
        XCTAssertEqual(pulls, 1)
        XCTAssertEqual(controller.lastFetchedRecordCount, 4)
        XCTAssertEqual(controller.observedCloudRecordCount, 4)
        XCTAssertNotNil(controller.lastSuccessAt)
        XCTAssertEqual(device.store.session, local)

        controller.isEnabled = false
        for _ in 0..<100 where await transport.stopCount == 0 { await Task.yield() }
        await transport.emit(.fetched(recordCount: 99))
        await transport.emit(.idle)
        await controller.pullFromICloud()
        let pullsAfterStop = await transport.pullCount
        XCTAssertEqual(pullsAfterStop, 1)
        XCTAssertEqual(controller.phase, .disabled)
        XCTAssertEqual(controller.lastFetchedRecordCount, 4)
    }

    func testDisablingSyncCancelsASuspendedPullWithoutReportingSuccess() async throws {
        let factory = TestBrowserCloudSyncTransportFactory(suspendsPull: true)
        let controller = BrowserCloudSyncController(
            core: CrestCore(), configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available), transportFactory: factory
        )
        await controller.start()
        let transport = try XCTUnwrap(factory.transports.first)
        let pull = Task { await controller.pullFromICloud() }
        for _ in 0..<1_000 where !(await transport.isPullSuspended) { await Task.yield() }
        let suspended = await transport.isPullSuspended
        XCTAssertTrue(suspended)
        controller.isEnabled = false
        await pull.value
        XCTAssertEqual(controller.phase, .disabled)
        XCTAssertNil(controller.lastSuccessAt)
        XCTAssertNil(controller.observedCloudRecordCount)
    }

    func testFailedPullDoesNotReportSuccessOrReplaceEitherCopy() async throws {
        let device = try await syncedDevice()
        let local = try device.storedJournal()
        let controller = BrowserCloudSyncController(
            core: device.core, configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available),
            transportFactory: TestBrowserCloudSyncTransportFactory(
                syncFailure: TestBrowserCloudSyncRemoteService.TestFailure.unavailable)
        )
        await controller.start()
        await controller.pullFromICloud()
        XCTAssertNotEqual(controller.phase, .ready)
        XCTAssertNil(controller.lastSuccessAt)
        XCTAssertNil(controller.observedCloudRecordCount)
        XCTAssertEqual(try device.storedJournal(), local)
    }

    private var testConfiguration: BrowserCloudSyncConfiguration {
        BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest")
    }

    /// A device whose file holds `session`, its launch staged: the core the
    /// controller reads and tells.
    private func syncedDevice(_ session: BrowserSession = .preview) async throws -> BrowserStoredSessionHarness {
        let device = try BrowserStoredSessionHarness(session: session, journal: BrowserSyncJournal())
        await device.store.flushPendingSyncPersistence()
        return device
    }

    /// What another device holding `session` keeps in iCloud.
    private func cloudRecords(of session: BrowserSession) throws -> [BrowserSyncRecord] {
        var journal = BrowserSyncJournal(deviceID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!)
        try journal.stage(session: session)
        return journal.records
    }
}

@MainActor
private final class TestBrowserCloudSyncPreferences: BrowserCloudSyncPreferences {
    var storedIsEnabled: Bool?
    var requiresConfirmation: Bool
    private(set) var resetCount = 0
    private(set) var savedConflictResolutions: [BrowserCloudConflictResolution?] = []

    init(
        storedIsEnabled: Bool? = nil,
        requiresAccountConfirmation: Bool = false
    ) {
        self.storedIsEnabled = storedIsEnabled
        requiresConfirmation = requiresAccountConfirmation
    }

    func loadIsEnabled() -> Bool? { storedIsEnabled }

    func saveIsEnabled(_ isEnabled: Bool) {
        storedIsEnabled = isEnabled
    }

    func requiresAccountConfirmation() throws -> Bool {
        requiresConfirmation
    }

    func resetTransportState() throws {
        resetCount += 1
        requiresConfirmation = false
    }

    func saveConflictResolution(_ resolution: BrowserCloudConflictResolution?) throws {
        savedConflictResolutions.append(resolution)
        requiresConfirmation = false
    }
}

private actor TestBrowserCloudSyncRemoteService: BrowserCloudSyncRemoteService {
    enum TestFailure: Error {
        case unavailable
    }

    private let hasEntitlement: Bool
    private var state: BrowserCloudAccountState
    private let snapshot: [BrowserSyncRecord]
    private let suspendsAccountState: Bool
    private var initialFailures: Int
    private var isSuspended = false
    private var wasReleased = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    var isSuspendedForTesting: Bool { isSuspended }

    init(
        hasEntitlement: Bool = true,
        accountState: BrowserCloudAccountState,
        snapshot: [BrowserSyncRecord] = [],
        suspendsAccountState: Bool = false,
        initialFailures: Int = 0
    ) {
        self.hasEntitlement = hasEntitlement
        state = accountState
        self.snapshot = snapshot
        self.suspendsAccountState = suspendsAccountState
        self.initialFailures = initialFailures
    }

    func hasRequiredEntitlement() async -> Bool { hasEntitlement }

    func accountState() async throws -> BrowserCloudAccountState {
        if suspendsAccountState, !wasReleased {
            isSuspended = true
            await withCheckedContinuation { releaseWaiters.append($0) }
            isSuspended = false
        }
        if initialFailures > 0 {
            initialFailures -= 1
            throw TestFailure.unavailable
        }
        return state
    }

    func loadSnapshot() async throws -> [BrowserSyncRecord] { snapshot }

    func release() {
        wasReleased = true
        let waiters = releaseWaiters
        releaseWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func signIn() {
        state = .available
    }

    nonisolated func message(for error: any Error) -> String {
        String(describing: error)
    }
}

@MainActor
private final class TestBrowserCloudSyncTransportFactory: BrowserCloudSyncTransportFactory {
    private(set) var transports: [TestBrowserCloudSyncTransport] = []
    private let syncFailure: (any Error)?
    private let suspendsPull: Bool

    init(syncFailure: (any Error)? = nil, suspendsPull: Bool = false) {
        self.syncFailure = syncFailure
        self.suspendsPull = suspendsPull
    }

    func makeTransport(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void
    ) throws -> any BrowserCloudSyncTransport {
        let transport = TestBrowserCloudSyncTransport(
            statusHandler: statusHandler,
            activityHandler: activityHandler,
            syncFailure: syncFailure,
            suspendsPull: suspendsPull
        )
        transports.append(transport)
        return transport
    }
}

private actor TestBrowserCloudSyncTransport: BrowserCloudSyncTransport {
    private(set) var startCount = 0
    private(set) var syncCount = 0
    private(set) var notifyCount = 0
    private(set) var pullCount = 0
    private(set) var stopCount = 0
    private let suspendsPull: Bool
    private var pullWaiter: CheckedContinuation<Void, Never>?
    var isPullSuspended: Bool { pullWaiter != nil }
    private let statusHandler: @Sendable (BrowserCloudSyncStatus) async -> Void
    private let activityHandler: @Sendable (BrowserCloudSyncActivity) async -> Void
    private let syncFailure: (any Error)?

    init(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void,
        syncFailure: (any Error)? = nil,
        suspendsPull: Bool = false
    ) {
        self.statusHandler = statusHandler
        self.activityHandler = activityHandler
        self.syncFailure = syncFailure
        self.suspendsPull = suspendsPull
    }

    func start() async {
        startCount += 1
        await statusHandler(.idle)
    }

    func syncNow() async throws {
        syncCount += 1
        await statusHandler(.syncing)
        if let syncFailure {
            await statusHandler(.failed(String(describing: syncFailure)))
            throw syncFailure
        }
        await statusHandler(.idle)
    }

    func stop() async {
        stopCount += 1
        pullWaiter?.resume()
        pullWaiter = nil
    }

    func pullFromICloud() async throws -> Int {
        pullCount += 1
        if suspendsPull { await withCheckedContinuation { pullWaiter = $0 } }
        if stopCount > 0 { throw CancellationError() }
        if let syncFailure { throw syncFailure }
        return 4
    }

    func notifyLocalChanges() async {
        notifyCount += 1
    }

    func emit(_ activity: BrowserCloudSyncActivity) async {
        await activityHandler(activity)
    }

    func emit(_ status: BrowserCloudSyncStatus) async {
        await statusHandler(status)
    }
}
