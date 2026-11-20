import CloudKit
import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCloudSyncControllerTests: XCTestCase {
    /// A core that cannot answer for this device's journal stops the start
    /// before anything reaches iCloud: its refusal never reads as a device
    /// with nothing to keep, which would take the cloud's content instead.
    func testAComparisonTheCoreRefusesStopsSyncWithoutTakingTheCloud() async throws {
        let core = try awaitingAccountDecision(CrestCore())
        let preferences = TestBrowserCloudSyncPreferences()
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: TestBrowserCloudSyncRemoteService(
                accountState: .available,
                snapshot: try await cloudRecords(of: SessionState.Seed(spaces: [.blank(number: 1)]))),
            transportFactory: factory
        )

        await controller.start()

        guard controller.phase == .failed else { return XCTFail("Sync started over a refused comparison.") }
        XCTAssertTrue(factory.transports.isEmpty)
        XCTAssertNil(controller.conflict)
        XCTAssertTrue(try core.query(CloudTransport()).awaitsAccountDecision)
    }

    private var testConfiguration: BrowserCloudSyncConfiguration {
        BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest")
    }

    /// What another device holding `session` keeps in iCloud.
    /// `core`, with its transport waiting for the person's account decision.
    private func awaitingAccountDecision(_ core: CrestCore) throws -> CrestCore {
        try core.transport(OpenCloudTransport(recordSchema: BrowserCloudRecordCodec.currentSchemaVersion, legacy: nil))
        try core.transport(ObserveCloudAccountChange(transition: .switchAccounts))
        return core
    }

    private func cloudRecords(of session: SessionState.Seed) async throws -> [SyncRecord] {
        let other = try BrowserStoredSessionHarness(
            seed: session, syncDeviceID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!)
        return try await other.pendingRecords()
    }
}

@MainActor
private final class TestBrowserCloudSyncPreferences: BrowserCloudSyncPreferences {
    var storedIsEnabled: Bool?

    init(storedIsEnabled: Bool? = nil) {
        self.storedIsEnabled = storedIsEnabled
    }

    func loadIsEnabled() -> Bool? { storedIsEnabled }

    func saveIsEnabled(_ isEnabled: Bool) {
        storedIsEnabled = isEnabled
    }
}

private actor TestBrowserCloudSyncRemoteService: BrowserCloudSyncRemoteService {
    private let state: CloudAccountState
    private let snapshot: [SyncRecord]

    init(accountState: CloudAccountState, snapshot: [SyncRecord] = []) {
        state = accountState
        self.snapshot = snapshot
    }

    func hasRequiredEntitlement() async -> Bool { true }

    func accountState() async throws -> CloudAccountState { state }

    func loadSnapshot() async throws -> [SyncRecord] { snapshot }

    nonisolated func message(for error: any Error) -> String {
        String(describing: error)
    }
}

@MainActor
private final class TestBrowserCloudSyncTransportFactory: BrowserCloudSyncTransportFactory {
    private(set) var transports: [TestBrowserCloudSyncTransport] = []

    func makeTransport(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void
    ) throws -> any BrowserCloudSyncTransport {
        let transport = TestBrowserCloudSyncTransport(statusHandler: statusHandler)
        transports.append(transport)
        return transport
    }
}

private actor TestBrowserCloudSyncTransport: BrowserCloudSyncTransport {
    private let statusHandler: @Sendable (BrowserCloudSyncStatus) async -> Void

    init(statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void) {
        self.statusHandler = statusHandler
    }

    func start() async {
        await statusHandler(.idle)
    }

    func syncNow() async throws {
        await statusHandler(.idle)
    }

    func stop() async {}

    func pullFromICloud() async throws -> Int { 0 }

    func notifyLocalChanges() async {}
}
