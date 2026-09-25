import CloudKit
import Foundation
import XCTest

@testable import Crest

final class BrowserCloudSyncStateTests: XCTestCase {
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
            ["recordSchemaVersion", "systemFields", "reconciliationReason", "conflictResolution", "requiresFullPull"]
        )
        XCTAssertEqual(object["reconciliationReason"] as? String, "accountChange")
        XCTAssertEqual(object["conflictResolution"] as? String, "useThisDevice")
        XCTAssertNil(object["requiresAccountConfirmation"])
    }

    func testSchemaUpgradeDiscardsCursorAndChangeTagsButKeepsAccountDecision() throws {
        let record = try BrowserCloudRecordCodec().record(for: testSpaceRecord(index: 6))
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
        XCTAssertEqual(encoded["recordSchemaVersion"] as? Int, BrowserCloudRecordCodec.currentSchemaVersion)
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
            service.message(for: BrowserCloudSyncError.remoteChangeNotApplied("boom")),
            "Crest couldn’t apply the latest changes from iCloud."
        )
    }

    @MainActor
    func testFailedMergeSurvivesRestartUntilAFullSnapshotIsApplied() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileBrowserCloudSyncStatePersistence(fileURL: directory.appendingPathComponent("state.json"))
        let harness = try BrowserStoredSessionHarness(session: .preview, journal: BrowserSyncJournal())
        await harness.store.flushPendingSyncPersistence()
        // The core cannot save the merge's journal, so it refuses the merge.
        try harness.refuseWrites(to: "journal")
        let engine = try BrowserCloudSyncEngine(
            configuration: BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest"),
            core: harness.core, persistence: persistence, automaticallySync: false
        )
        do {
            try await engine.mergeDownloadedRecords([testSpaceRecord(index: 1)])
            XCTFail("Expected local persistence failure")
        } catch {}
        XCTAssertTrue(try XCTUnwrap(persistence.load()).requiresFullPull)

        try harness.acceptWrites()
        let restarted = try BrowserCloudSyncEngine(
            configuration: BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest"),
            core: harness.core, persistence: persistence, automaticallySync: false
        )
        try await restarted.mergeDownloadedRecords([testSpaceRecord(index: 2)])
        XCTAssertTrue(try XCTUnwrap(persistence.load()).requiresFullPull)
        try await restarted.mergeDownloadedRecords(
            [testSpaceRecord(index: 1), testSpaceRecord(index: 2)], isFullSnapshot: true)
        XCTAssertFalse(try XCTUnwrap(persistence.load()).requiresFullPull)
    }

    /// A Space record as the cloud stores it.
    private func testSpaceRecord(index: Int) -> SyncRecord {
        let id = testUUID(prefix: 5, index: index)
        let value: [String: Any] = [
            "id": ["rawValue": id.uuidString], "profileID": testUUID(prefix: 6, index: index).uuidString,
            "name": "Space \(index)", "symbol": "square.grid.2x2.fill", "accent": "indigo", "orderToken": "a",
        ]
        let body = try! JSONSerialization.data(withJSONObject: ["type": "space", "value": value], options: [.sortedKeys])
        return SyncRecord(
            kind: .space, id: id, spaceID: id, version: SyncVersion(clock: UInt64(index), deviceID: testUUID(prefix: 7, index: 1)),
            schema: 1, body: body, isTombstone: false)
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
