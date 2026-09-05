import CloudKit
import Foundation
import XCTest

@testable import Crest

final class BrowserCloudSyncStateTests: XCTestCase {
    func testCloudTransportUsesTheCrestContainerConfiguredByBothApps() throws {
        let configuration = try XCTUnwrap(BrowserCloudSyncConfiguration.configured())

        XCTAssertEqual(configuration.containerIdentifier, "iCloud.com.pauldavis.crest")
    }

    func testCloudContainerEntitlementMustAuthorizeTheConfiguredContainer() {
        let identifier = "iCloud.com.pauldavis.crest"

        XCTAssertTrue(
            BrowserCloudContainerEntitlementPolicy.containsContainer(
                identifier,
                entitlementValue: [identifier, "iCloud.com.pauldavis.other"]
            )
        )
        XCTAssertFalse(
            BrowserCloudContainerEntitlementPolicy.containsContainer(
                identifier,
                entitlementValue: ["iCloud.com.pauldavis.other"]
            )
        )
        XCTAssertFalse(
            BrowserCloudContainerEntitlementPolicy.containsContainer(
                identifier,
                entitlementValue: nil
            )
        )
    }

    func testInitialCloudSignInDoesNotMasqueradeAsAnAccountConflict() {
        XCTAssertFalse(
            BrowserCloudAccountChangePolicy.requiresReconciliation(
                for: .signIn,
                alreadyRequiresReconciliation: false
            )
        )
        XCTAssertTrue(
            BrowserCloudAccountChangePolicy.requiresReconciliation(
                for: .signIn,
                alreadyRequiresReconciliation: true
            )
        )
        XCTAssertTrue(
            BrowserCloudAccountChangePolicy.requiresReconciliation(
                for: .signOut,
                alreadyRequiresReconciliation: false
            )
        )
        XCTAssertTrue(
            BrowserCloudAccountChangePolicy.requiresReconciliation(
                for: .switchAccounts,
                alreadyRequiresReconciliation: false
            )
        )
        XCTAssertTrue(
            BrowserCloudAccountChangePolicy.requiresReconciliation(
                for: .unknown,
                alreadyRequiresReconciliation: false
            )
        )
    }

    func testResetLaunchesUseIsolatedStoresAndNeverReachCloudKit() {
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: ["CREST_RESET_SESSION": "1"],
                    isXCTestRuntime: false
                )
            )
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(values: [:], isXCTestRuntime: true)
            )
        )
        XCTAssertFalse(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false)
            )
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: [
                        "CREST_RESET_SESSION": "1",
                        "CREST_PERFORMANCE_BASE_URL": "http://127.0.0.1:8080/",
                    ],
                    isXCTestRuntime: false
                )
            )
        )
    }

    func testCloudTransportStateRoundTripsThroughItsIndependentStore() throws {
        let suiteName = "BrowserCloudSyncStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserCloudSyncStatePersistence(
            defaults: defaults,
            key: "state"
        )
        let record = CKRecord(
            recordType: "CrestSpace",
            recordID: CKRecord.ID(
                recordName: "space:40000000-0000-0000-0000-000000000001",
                zoneID: BrowserCloudRecordCodec.zoneID
            )
        )
        var fields = BrowserCloudRecordSystemFields()
        fields.update(with: record)
        let state = BrowserCloudSyncState(
            systemFields: fields,
            reconciliationReason: .accountChange
        )

        try persistence.save(state)
        let restored = try XCTUnwrap(persistence.load())

        XCTAssertTrue(restored.requiresAccountConfirmation)
        XCTAssertEqual(restored.reconciliationReason, .accountChange)
        XCTAssertNotNil(restored.systemFields.record(for: record.recordID))
        XCTAssertNil(restored.engineStateSerialization)
    }

    func testCloudTransportStateKeepsItsStableSerializedKeysAndRawValues() throws {
        let state = BrowserCloudSyncState(
            reconciliationReason: .accountChange,
            conflictResolution: .useThisDevice
        )

        let data = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            ["recordSchemaVersion", "systemFields", "reconciliationReason", "conflictResolution"]
        )
        XCTAssertEqual(object["reconciliationReason"] as? String, "accountChange")
        XCTAssertEqual(object["conflictResolution"] as? String, "useThisDevice")
        XCTAssertNil(object["requiresAccountConfirmation"])
    }

    func testSchemaUpgradeDiscardsCursorAndChangeTagsButKeepsAccountDecision() throws {
        let record = try BrowserCloudRecordCodec().encode(testSpaceRecord(index: 6))
        var fields = BrowserCloudRecordSystemFields()
        fields.update(with: record)
        let state = BrowserCloudSyncState(systemFields: fields, reconciliationReason: .accountChange)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "recordSchemaVersion")
        // The old cursor is opaque. Upgrading must discard it before decoding,
        // otherwise records previously skipped by schema 1 never get replayed.
        object["engineStateSerialization"] = "opaque cursor from older SDK"
        let upgraded = try JSONDecoder().decode(
            BrowserCloudSyncState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(upgraded.engineStateSerialization)
        XCTAssertNil(upgraded.systemFields.record(for: record.recordID))
        XCTAssertTrue(upgraded.requiresAccountConfirmation)
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(upgraded)) as? [String: Any])
        XCTAssertEqual(encoded["recordSchemaVersion"] as? Int, 2)
    }

    func testCloudTransportUsesItsStableDefaultsKey() throws {
        let suiteName = "BrowserCloudSyncStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserCloudSyncStatePersistence(
            defaults: defaults
        )

        try persistence.save(BrowserCloudSyncState())

        XCTAssertNotNil(defaults.data(forKey: "crest.cloud-sync.state.v1"))
    }

    func testLegacyRecordConflictPauseMigratesToAutomaticReconciliation() throws {
        let data = Data(
            """
            {
              "requiresAccountConfirmation": true,
              "systemFields": { "encodedRecordsByName": {} }
            }
            """.utf8
        )

        let restored = try JSONDecoder().decode(BrowserCloudSyncState.self, from: data)

        XCTAssertEqual(restored.reconciliationReason, .legacyRecordConflict)
        XCTAssertFalse(restored.requiresAccountConfirmation)
    }

    func testUsingThisDeviceSurvivesRestartWithoutReopeningTheApprovedConflict() throws {
        let suiteName = "BrowserCloudSyncStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserCloudSyncStatePersistence(
            defaults: defaults,
            key: "state"
        )

        try persistence.save(
            BrowserCloudSyncState(conflictResolution: .useThisDevice)
        )
        let restored = try XCTUnwrap(persistence.load())

        XCTAssertEqual(restored.conflictResolution, .useThisDevice)
        XCTAssertFalse(
            BrowserCloudConflictResolutionPolicy.shouldMergeFetchedContent(
                resolution: restored.conflictResolution
            )
        )
    }

    func testCompletedUseDeviceResolutionClearsBeforeFutureDownloads() {
        let resolution = BrowserCloudConflictResolutionPolicy.resolutionAfterRestart(
            persistedResolution: .useThisDevice,
            hasPendingUploads: false
        )

        XCTAssertNil(resolution)
        XCTAssertTrue(
            BrowserCloudConflictResolutionPolicy.shouldMergeFetchedContent(
                resolution: resolution
            )
        )
        XCTAssertEqual(
            BrowserCloudConflictResolutionPolicy.resolutionAfterRestart(
                persistedResolution: .useThisDevice,
                hasPendingUploads: true
            ),
            .useThisDevice
        )
    }

    /// The change token advances whether or not a fetched batch was applied, so a
    /// batch abandoned over one unreadable record is never offered again. Every
    /// record has to get its own chance.
    func testOneUnreadableRecordDoesNotCostTheRestOfItsBatch() throws {
        let codec = BrowserCloudRecordCodec()
        let first = try codec.encode(testSpaceRecord(index: 1))
        let broken = try codec.encode(testSpaceRecord(index: 2))
        let last = try codec.encode(testSpaceRecord(index: 3))
        broken.encryptedValues["payload"] = Data("not-json".utf8) as CKRecordValue

        let batch = BrowserCloudSyncEngine.fetchedBatch(
            decoding: [first, broken, last]
        )

        XCTAssertEqual(
            batch.records.map(\.id.recordName),
            [first.recordID.recordName, last.recordID.recordName]
        )
        XCTAssertEqual(batch.undecodableRecordNames, [broken.recordID.recordName])
        XCTAssertTrue(batch.newerSchemaRecordNames.isEmpty)
    }

    /// One record written by a newer build of Crest used to break sync for every
    /// older device. It is skipped now, and it says why.
    func testARecordFromANewerSchemaIsSkippedWithAnUpdateSignal() throws {
        let codec = BrowserCloudRecordCodec()
        let current = try codec.encode(testSpaceRecord(index: 4))
        let newer = try codec.encode(testSpaceRecord(index: 5))
        newer["schemaVersion"] = NSNumber(
            value: BrowserCloudRecordCodec.currentSchemaVersion + 1
        )

        let batch = BrowserCloudSyncEngine.fetchedBatch(decoding: [newer, current])

        XCTAssertEqual(
            batch.records.map(\.id.recordName),
            [current.recordID.recordName]
        )
        XCTAssertEqual(batch.newerSchemaRecordNames, [newer.recordID.recordName])
        XCTAssertTrue(batch.undecodableRecordNames.isEmpty)
    }

    func testRemovingCrestsICloudDataIsNotImmediatelyUndone() {
        XCTAssertFalse(
            BrowserCloudSyncEngine.restoresLocalRecords(afterZoneDeletion: .purged)
        )
        XCTAssertFalse(
            BrowserCloudSyncEngine.restoresLocalRecords(afterZoneDeletion: .deleted)
        )
        XCTAssertTrue(
            BrowserCloudSyncEngine.restoresLocalRecords(
                afterZoneDeletion: .encryptedDataReset
            )
        )
    }

    func testAFailedFetchEventReportsWhyRatherThanClaimingSuccess() {
        let service = CloudKitBrowserCloudSyncRemoteService(
            configuration: BrowserCloudSyncConfiguration(
                containerIdentifier: "iCloud.com.pauldavis.crest"
            )
        )

        XCTAssertEqual(
            service.message(for: BrowserSyncError.remoteChangeNotApplied("boom")),
            "Crest couldn’t apply the latest changes from iCloud."
        )
    }

    private func testSpaceRecord(index: Int) -> BrowserSyncRecord {
        let space = BrowserSyncSpace(
            id: SpaceID(rawValue: testUUID(prefix: 5, index: index)),
            profileID: testUUID(prefix: 6, index: index),
            name: "Space \(index)",
            symbol: "square.grid.2x2.fill",
            accent: .indigo,
            orderToken: "a"
        )
        return .save(
            .space(space),
            version: BrowserSyncVersion(
                logicalClock: UInt64(index),
                deviceID: testUUID(prefix: 7, index: 1)
            )
        )
    }

    private func testUUID(prefix: Int, index: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "%d0000000-0000-0000-0000-%012d",
                prefix,
                index
            )
        )!
    }

    func testCloudTransportStateRejectsCorruptData() throws {
        let suiteName = "BrowserCloudSyncStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserCloudSyncStatePersistence(
            defaults: defaults,
            key: "state"
        )
        defaults.set(Data("corrupt".utf8), forKey: "state")

        XCTAssertThrowsError(try persistence.load()) { error in
            XCTAssertEqual(error as? BrowserCloudSyncStatePersistenceError, .decodingFailed)
        }
    }

    func testFileStatePersistenceRoundTripsThroughTheFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileBrowserCloudSyncStatePersistence(
            fileURL: directory.appendingPathComponent("state.json")
        )

        var state = BrowserCloudSyncState()
        state.conflictResolution = .useThisDevice
        try persistence.save(state)

        let loaded = try XCTUnwrap(persistence.load())
        XCTAssertEqual(loaded.conflictResolution, .useThisDevice)
    }

    func testFileStatePersistenceMigratesTheDefaultsBlobAndRetiresTheKey() throws {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var legacy = BrowserCloudSyncState()
        legacy.reconciliationReason = .accountChange
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: UserDefaultsBrowserCloudSyncStatePersistence.defaultKey
        )

        let fileURL = directory.appendingPathComponent("state.json")
        let persistence = FileBrowserCloudSyncStatePersistence(
            fileURL: fileURL,
            migrationDefaults: defaults
        )

        // Migration reads the blob, writes the file, and retires the old key so
        // the preferences plist shrinks back below the CFPreferences cap.
        let migrated = try XCTUnwrap(persistence.load())
        XCTAssertEqual(migrated.reconciliationReason, .accountChange)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(
            defaults.data(
                forKey: UserDefaultsBrowserCloudSyncStatePersistence.defaultKey
            )
        )

        // Subsequent loads come from the file alone.
        let reloaded = try XCTUnwrap(persistence.load())
        XCTAssertEqual(reloaded.reconciliationReason, .accountChange)
    }

}
