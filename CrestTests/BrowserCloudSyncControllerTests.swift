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
            browser: BrowserStore.preview(),
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

    func testStoredDisabledPreferenceStartsInTheDisabledPhase() throws {
        let suiteName = "BrowserCloudSyncControllerTests.Disabled.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "sync-enabled")

        let controller = BrowserCloudSyncController(
            browser: BrowserStore.preview(),
            configuration: nil,
            defaults: defaults,
            enabledKey: "sync-enabled"
        )

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.phase, .disabled)
    }

    func testAvailableAccountStartsAutomaticTransportWithoutForcingAManualSync() async throws {
        let workflow = TestBrowserCloudSyncWorkflowGateway()
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .available)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            workflow: workflow,
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

    func testUnavailableAccountWaitsWithoutCreatingATransport() async {
        let workflow = TestBrowserCloudSyncWorkflowGateway()
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .noAccount)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            workflow: workflow,
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
        let local = testRecord(index: 1)
        let cloud = testRecord(index: 2)
        let workflow = TestBrowserCloudSyncWorkflowGateway(records: [local])
        let preferences = TestBrowserCloudSyncPreferences(
            requiresAccountConfirmation: true
        )
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: [cloud]
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            workflow: workflow,
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
                localRecordCount: 1,
                cloudRecordCount: 1,
                localSpaceCount: 0,
                cloudSpaceCount: 0
            )
        )
        XCTAssertEqual(controller.observedCloudRecordCount, 1)
        XCTAssertTrue(factory.transports.isEmpty)
        XCTAssertTrue(workflow.replacedLocalSnapshots.isEmpty)
        XCTAssertTrue(workflow.preparedCloudSnapshots.isEmpty)
    }

    func testUseICloudResolutionReplacesLocalContentAndClearsThePause() async throws {
        let local = testRecord(index: 1)
        let cloud = testRecord(index: 2)
        let workflow = TestBrowserCloudSyncWorkflowGateway(records: [local])
        let preferences = TestBrowserCloudSyncPreferences(
            requiresAccountConfirmation: true
        )
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: [cloud]
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            workflow: workflow,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        await controller.start()

        await controller.resolveUsingICloud()

        XCTAssertEqual(workflow.replacedLocalSnapshots, [[cloud]])
        XCTAssertTrue(workflow.preparedCloudSnapshots.isEmpty)
        XCTAssertEqual(preferences.savedConflictResolutions.count, 1)
        XCTAssertNil(preferences.savedConflictResolutions[0])
        XCTAssertNil(controller.conflict)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testUseThisDeviceResolutionStagesAnOverwriteAndPersistsTheChoice() async throws {
        let local = testRecord(index: 1)
        let cloud = testRecord(index: 2)
        let workflow = TestBrowserCloudSyncWorkflowGateway(records: [local])
        let preferences = TestBrowserCloudSyncPreferences(
            requiresAccountConfirmation: true
        )
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: [cloud]
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            workflow: workflow,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        await controller.start()

        await controller.resolveUsingThisDevice()

        XCTAssertTrue(workflow.replacedLocalSnapshots.isEmpty)
        XCTAssertEqual(workflow.preparedCloudSnapshots, [[cloud]])
        XCTAssertEqual(preferences.savedConflictResolutions, [.useThisDevice])
        XCTAssertNil(controller.conflict)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testDisposableSeedIsReplacedBeforeTransportStarts() async throws {
        let cloud = testRecord(index: 2)
        let workflow = TestBrowserCloudSyncWorkflowGateway(
            hasDisposableSeed: true
        )
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: [cloud]
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            workflow: workflow,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )

        await controller.start()

        XCTAssertEqual(workflow.replacedDisposableSeedSnapshots, [[cloud]])
        XCTAssertEqual(preferences.resetCount, 1)
        XCTAssertEqual(controller.observedCloudRecordCount, 1)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testAccountChangeDiscardsTheTransportAndRestartsAgainstTheCurrentAccount() async throws {
        let workflow = TestBrowserCloudSyncWorkflowGateway()
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .available)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            workflow: workflow,
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
            workflow: TestBrowserCloudSyncWorkflowGateway(),
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

    func testTurningSyncOffWithNoPendingDecisionStillClearsTransportState() async throws {
        let preferences = TestBrowserCloudSyncPreferences()
        let controller = BrowserCloudSyncController(
            workflow: TestBrowserCloudSyncWorkflowGateway(),
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available),
            transportFactory: TestBrowserCloudSyncTransportFactory()
        )

        controller.isEnabled = false
        for _ in 0..<100 where controller.phase != .disabled {
            await Task.yield()
        }

        XCTAssertEqual(preferences.resetCount, 1)
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
            workflow: TestBrowserCloudSyncWorkflowGateway(),
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
            workflow: TestBrowserCloudSyncWorkflowGateway(),
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
            workflow: TestBrowserCloudSyncWorkflowGateway(),
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
            workflow: TestBrowserCloudSyncWorkflowGateway(),
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
            workflow: TestBrowserCloudSyncWorkflowGateway(),
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
            workflow: TestBrowserCloudSyncWorkflowGateway(),
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
            workflow: TestBrowserCloudSyncWorkflowGateway(),
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

    func testEnabledPreferenceRetainsItsStableDefaultsKey() throws {
        let suiteName = "BrowserCloudSyncControllerTests.EnabledKey.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsBrowserCloudSyncPreferences(defaults: defaults)

        preferences.saveIsEnabled(false)

        XCTAssertEqual(defaults.object(forKey: "crest.cloud-sync.enabled") as? Bool, false)
        XCTAssertEqual(preferences.loadIsEnabled(), false)
    }

    func testDiagnosticsRetainTheirPrivacyPreservingFieldsAndFormatting() {
        let diagnostics = BrowserCloudSyncDiagnostics(
            containerIdentifier: "iCloud.com.pauldavis.crest",
            isEnabled: true,
            accountState: .available,
            phase: .ready,
            localRecordCount: 8,
            pendingUploadCount: 2,
            observedCloudRecordCount: 7,
            lastAttemptAt: Date(timeIntervalSince1970: 0),
            lastSuccessAt: nil,
            lastFetchedRecordCount: 3,
            lastUploadedRecordCount: 4,
            hasError: false,
            requiresReconciliation: false,
            skippedRecordCount: 0,
            requiresAppUpdate: false,
            cloudDataWasRemoved: false
        )

        XCTAssertEqual(
            diagnostics.report,
            """
            Crest iCloud Sync Diagnostics
            Container: iCloud.com.pauldavis.crest
            Enabled: true
            Account: Available
            Status: Up to date
            Local records: 8
            Pending uploads: 2
            Cloud records observed: 7
            Last attempt: 1970-01-01T00:00:00Z
            Last success: Never
            Last download batch: 3
            Last upload batch: 4
            Error present: false
            Reconciliation required: false
            Records skipped: 0
            Needs app update: false
            iCloud data removed: false
            """
        )
    }

    func testCloudKitFailuresRetainTheirFriendlyMessages() {
        let service = CloudKitBrowserCloudSyncRemoteService(
            configuration: testConfiguration
        )

        XCTAssertEqual(
            service.message(for: CKError(.notAuthenticated)),
            "Sign in to iCloud to sync Crest."
        )
        XCTAssertEqual(
            service.message(for: CKError(.networkFailure)),
            "Crest can’t reach iCloud right now."
        )
        XCTAssertEqual(
            service.message(for: CKError(.quotaExceeded)),
            "Your iCloud storage is full."
        )
        XCTAssertEqual(
            service.message(for: CKError(.permissionFailure)),
            "This build is not permitted to use Crest’s iCloud container."
        )
        XCTAssertEqual(
            service.message(for: CKError(.serviceUnavailable)),
            "iCloud is temporarily unavailable. Crest will retry automatically."
        )
        XCTAssertEqual(
            service.message(for: CKError(.requestRateLimited)),
            "iCloud is temporarily busy. Crest will retry automatically."
        )
    }

    private var testConfiguration: BrowserCloudSyncConfiguration {
        BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest")
    }

    private func testRecord(index: UInt64) -> BrowserSyncRecord {
        let spaceID = SpaceID(
            rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        )
        let value = UUID(
            uuidString: String(
                format: "20000000-0000-0000-0000-%012d",
                Int(index)
            )
        )!
        return .delete(
            id: BrowserSyncRecordID(kind: .history, value: value),
            spaceID: spaceID,
            version: BrowserSyncVersion(
                logicalClock: index,
                deviceID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
            ),
            reason: .retention,
            at: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }
}

@MainActor
private final class TestBrowserCloudSyncWorkflowGateway: BrowserCloudSyncWorkflowGateway {
    var hasDisposableCloudSyncSeed: Bool
    var cloudSyncLocalRecordCount: Int { records.count }
    var cloudSyncPendingRecordCount = 0
    var cloudSyncLocalErrorDescription: String?
    private var records: [BrowserSyncRecord]
    private(set) var replacedLocalSnapshots: [[BrowserSyncRecord]] = []
    private(set) var replacedDisposableSeedSnapshots: [[BrowserSyncRecord]] = []
    private(set) var preparedCloudSnapshots: [[BrowserSyncRecord]] = []

    init(
        records: [BrowserSyncRecord] = [],
        hasDisposableSeed: Bool = false
    ) {
        self.records = records
        hasDisposableCloudSyncSeed = hasDisposableSeed
    }

    func cloudSyncRecords() async -> [BrowserSyncRecord] { records }

    func cloudSyncPendingRecordIDs() async -> Set<BrowserSyncRecordID> { [] }

    func mergeCloudSyncRecords(_ records: [BrowserSyncRecord]) async throws {
        self.records = records
    }

    func markCloudSyncRecordsUploaded(
        _: [BrowserSyncRecordID: BrowserSyncVersion]
    ) async throws {}

    func replaceLocalWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws {
        replacedLocalSnapshots.append(remoteRecords)
        records = remoteRecords
    }

    func replaceDisposableSeedWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws {
        replacedDisposableSeedSnapshots.append(remoteRecords)
        records = remoteRecords
        hasDisposableCloudSyncSeed = false
    }

    func prepareToOverwriteCloud(with remoteRecords: [BrowserSyncRecord]) throws {
        preparedCloudSnapshots.append(remoteRecords)
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

    init(syncFailure: (any Error)? = nil) {
        self.syncFailure = syncFailure
    }

    func makeTransport(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void
    ) throws -> any BrowserCloudSyncTransport {
        let transport = TestBrowserCloudSyncTransport(
            statusHandler: statusHandler,
            activityHandler: activityHandler,
            syncFailure: syncFailure
        )
        transports.append(transport)
        return transport
    }
}

private actor TestBrowserCloudSyncTransport: BrowserCloudSyncTransport {
    private(set) var startCount = 0
    private(set) var syncCount = 0
    private(set) var notifyCount = 0
    private let statusHandler: @Sendable (BrowserCloudSyncStatus) async -> Void
    private let activityHandler: @Sendable (BrowserCloudSyncActivity) async -> Void
    private let syncFailure: (any Error)?

    init(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void,
        syncFailure: (any Error)? = nil
    ) {
        self.statusHandler = statusHandler
        self.activityHandler = activityHandler
        self.syncFailure = syncFailure
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
