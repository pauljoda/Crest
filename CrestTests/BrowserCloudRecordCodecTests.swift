import CloudKit
import Foundation
import XCTest

@testable import Crest

final class BrowserCloudRecordCodecTests: XCTestCase {
    func testEveryAllowlistedRecordRoundTripsThroughCloudKit() throws {
        var session = BrowserSession.preview
        let rootFolder = try XCTUnwrap(session.spaces[0].folders.first)
        let nestedFolder = BrowserFolder(
            title: "Nested",
            symbol: "folder.fill",
            parentID: rootFolder.id,
            isCollapsed: true,
            collapseModifiedAt: Date(timeIntervalSince1970: 125)
        )
        session.spaces[0].folders.append(nestedFolder)
        session.spaces[0].isSavedTabsExpanded = false
        session.spaces[0].savedTabsExpansionModifiedAt = Date(
            timeIntervalSince1970: 126
        )
        session.spaces[0].branding = BrowserSpaceBranding(
            colors: [
                .ink,
                BrowserSpaceBrandColor(red: 0.08, green: 0.46, blue: 0.94),
                .gold,
            ],
            bannerPattern: .chevron,
            bannerStrength: 0.52,
            readabilityFade: 0.45,
            themeMode: .gradient,
            gradientAngle: 38,
            showsTexture: true,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(
                backplate: .shield,
                fieldDivision: .quarterly,
                ordinary: .bordure,
                trim: .laurel,
                symbol: .oak,
                chargeLayout: .single,
                backplateColorIndex: 0,
                secondaryFieldColorIndex: 1,
                ordinaryColorIndex: 2,
                trimColorIndex: 2,
                symbolColorIndex: 0
            )
        )
        for spaceIndex in session.spaces.indices {
            for tabIndex in session.spaces[spaceIndex].tabs.indices {
                session.spaces[spaceIndex].tabs[tabIndex].lastActivatedAt = Date(
                    timeIntervalSince1970: TimeInterval(10 + tabIndex)
                )
            }
        }
        let renamedID = try XCTUnwrap(session.spaces[0].tabs.first?.id)
        XCTAssertTrue(
            session.setTabCustomTitle(
                "Release Notes",
                tabID: renamedID,
                in: session.spaces[0].id,
                at: Date(timeIntervalSince1970: 150)
            )
        )
        session.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/history")),
            title: "History",
            at: Date(timeIntervalSince1970: 100)
        )
        let closedID = try XCTUnwrap(session.selectedSpace?.currentTabs.first?.id)
        session.closeTab(closedID, at: Date(timeIntervalSince1970: 200))
        var journal = BrowserSyncJournal(
            deviceID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        )
        try journal.stage(session: session, at: Date(timeIntervalSince1970: 300))
        let codec = BrowserCloudRecordCodec()

        let decoded = try journal.records.map { try codec.decode(codec.encode($0)) }

        XCTAssertEqual(decoded, journal.records)
        XCTAssertEqual(Set(decoded.map(\.id.kind)), Set(BrowserSyncRecordKind.allCases))
        XCTAssertTrue(
            decoded.contains { record in
                guard case .folder(let folder)? = record.payload else { return false }
                return folder.id == nestedFolder.id
                    && folder.parentID == rootFolder.id
                    && folder.isCollapsed
                    && folder.collapseModifiedAt == Date(timeIntervalSince1970: 125)
            })
        XCTAssertTrue(
            decoded.contains { record in
                guard case .space(let space)? = record.payload else { return false }
                return space.id == session.spaces[0].id
                    && space.branding == session.spaces[0].branding
                    && !space.isSavedTabsExpanded
                    && space.savedTabsExpansionModifiedAt
                        == Date(timeIntervalSince1970: 126)
            })
        XCTAssertTrue(
            decoded.contains { record in
                guard case .tab(let tab)? = record.payload,
                    tab.id == renamedID
                else { return false }
                return tab.customTitle == "Release Notes"
                    && tab.titleModifiedAt == Date(timeIntervalSince1970: 150)
            },
            "A renamed tab must survive the CloudKit encrypted payload round trip."
        )
    }

    /// The expanded charges ride CloudKit inside the encrypted Space payload. A
    /// crest has to arrive wearing the charge that was chosen, not the default
    /// one its decoder falls back to.
    func testExpandedChargesSurviveTheEncryptedPayloadRoundTrip() throws {
        var session = BrowserSession.preview
        let expanded: [BrowserSpaceCrestSymbol] = [
            .crown, .risingSun, .paw, .hound, .horn, .snowflake, .drop,
            .flower, .crossedBanners,
        ]
        for index in session.spaces.indices {
            session.spaces[index].branding.iconStyle = .layeredCrest
            session.spaces[index].branding.crest.symbol =
                expanded[
                    index % expanded.count
                ]
        }
        var journal = BrowserSyncJournal(
            deviceID: UUID(uuidString: "10000000-0000-0000-0000-000000000009")!
        )
        try journal.stage(session: session, at: Date(timeIntervalSince1970: 300))
        let codec = BrowserCloudRecordCodec()

        let decoded = try journal.records
            .filter { $0.id.kind == .space }
            .map { try codec.decode(codec.encode($0)) }

        XCTAssertFalse(decoded.isEmpty)
        for record in decoded {
            guard case .space(let space)? = record.payload,
                let source = session.spaces.first(where: { $0.id == space.id })
            else {
                return XCTFail("A Space record lost its payload in transit.")
            }
            XCTAssertEqual(space.branding, source.branding)
            XCTAssertEqual(space.branding.crest.symbol, source.branding.crest.symbol)
            XCTAssertTrue(expanded.contains(space.branding.crest.symbol))
            XCTAssertEqual(
                space.branding.renderingVersion,
                BrowserSpaceBranding.expandedChargeRenderingVersion
            )
        }
    }

    func testTombstoneRoundTripsWithoutAPayload() throws {
        let id = BrowserSyncRecordID(
            kind: .tab,
            value: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        )
        let spaceID = SpaceID(
            rawValue: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        )
        let source = BrowserSyncRecord.delete(
            id: id,
            spaceID: spaceID,
            version: BrowserSyncVersion(
                logicalClock: 42,
                deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
            ),
            reason: .explicitDelete,
            at: Date(timeIntervalSince1970: 500)
        )
        let codec = BrowserCloudRecordCodec()

        let cloudRecord = try codec.encode(source)
        let decoded = try codec.decode(cloudRecord)

        XCTAssertEqual(decoded, source)
        XCTAssertNil(decoded.payload)
        XCTAssertEqual(decoded.tombstone?.reason, .explicitDelete)
    }

    func testChildRecordCarriesAReferenceToItsOwningSpace() throws {
        let source = try makeTabRecord()
        let cloudRecord = try BrowserCloudRecordCodec().encode(source)
        let reference = try XCTUnwrap(cloudRecord["space"] as? CKRecord.Reference)

        XCTAssertEqual(reference.recordID.zoneID, BrowserCloudRecordCodec.zoneID)
        XCTAssertEqual(
            reference.recordID.recordName,
            BrowserSyncRecordID(kind: .space, value: source.spaceID.rawValue).recordName
        )
    }

    func testCodecReusesLastKnownServerRecordSystemFields() throws {
        let source = try makeTabRecord()
        let recordID = CKRecord.ID(
            recordName: source.id.recordName,
            zoneID: BrowserCloudRecordCodec.zoneID
        )
        let base = CKRecord(recordType: "CrestTab", recordID: recordID)

        let encoded = try BrowserCloudRecordCodec().encode(source, reusing: base)

        XCTAssertTrue(encoded === base)
        XCTAssertEqual(try BrowserCloudRecordCodec().decode(encoded), source)
        XCTAssertNil(encoded["payload"])
        XCTAssertNotNil(encoded.encryptedValues["payload"] as? Data)
    }

    func testCodecRejectsWrongZoneTypeAndIdentity() throws {
        let source = try makeTabRecord()
        let codec = BrowserCloudRecordCodec()
        let wrongZone = CKRecord(
            recordType: "CrestTab",
            recordID: CKRecord.ID(
                recordName: source.id.recordName,
                zoneID: CKRecordZone.ID(zoneName: "Other")
            )
        )
        XCTAssertThrowsError(try codec.decode(wrongZone)) { error in
            XCTAssertEqual(error as? BrowserCloudRecordCodecError, .unexpectedZone("Other"))
        }

        let wrongType = try codec.encode(source)
        let mismatched = CKRecord(
            recordType: "CrestFolder",
            recordID: wrongType.recordID
        )
        XCTAssertThrowsError(try codec.decode(mismatched)) { error in
            XCTAssertEqual(
                error as? BrowserCloudRecordCodecError,
                .malformedRecordName(source.id.recordName)
            )
        }
    }

    func testSystemFieldsPersistWithoutCopyingDomainPayload() throws {
        let source = try makeTabRecord()
        let cloudRecord = try BrowserCloudRecordCodec().encode(source)
        var fields = BrowserCloudRecordSystemFields()

        fields.update(with: cloudRecord)
        let restored = try XCTUnwrap(fields.record(for: cloudRecord.recordID))

        XCTAssertEqual(restored.recordID, cloudRecord.recordID)
        XCTAssertNil(restored["payload"])
        fields.remove(recordName: cloudRecord.recordID.recordName)
        XCTAssertNil(fields.record(for: cloudRecord.recordID))
    }

    func testOpenFolderRecordsDeclareTheirRequiredCloudSchema() throws {
        let original = try makeTabRecord()
        var tab = try XCTUnwrap(original.payload?.tabValue)
        let folder = BrowserSyncFolder(
            id: FolderID(), spaceID: tab.spaceID, title: "Open research",
            location: .current, symbol: "folder", orderToken: "a")
        tab.folderID = folder.id
        let records: [BrowserSyncRecord] = [
            .save(.folder(folder), version: original.version),
            .save(.tab(tab), version: original.version),
        ]
        for source in records {
            let cloud = try BrowserCloudRecordCodec().encode(source)
            XCTAssertEqual((cloud["schemaVersion"] as? NSNumber)?.intValue, 2)
            XCTAssertEqual(try BrowserCloudRecordCodec().decode(cloud), source)
        }
        let ordinary = try BrowserCloudRecordCodec().encode(original)
        XCTAssertEqual((ordinary["schemaVersion"] as? NSNumber)?.intValue, 1)
    }

    func testReturningAnOpenFolderToSavedAndDeletingItRemainLegacyReadable() throws {
        let source = try makeTabRecord()
        var folder = BrowserSyncFolder(
            id: FolderID(), spaceID: source.spaceID, title: "Research",
            location: .current, symbol: "folder", orderToken: "a")
        let open = BrowserSyncRecord.save(.folder(folder), version: source.version)
        let codec = BrowserCloudRecordCodec()
        let cloud = try codec.encode(open)
        XCTAssertEqual((cloud["schemaVersion"] as? NSNumber)?.intValue, 2)

        folder.location = .saved
        let saved = BrowserSyncRecord.save(
            .folder(folder), version: .init(logicalClock: 2, deviceID: source.version.deviceID))
        let promoted = try codec.encode(saved, reusing: cloud)
        XCTAssertEqual((promoted["schemaVersion"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(try codec.decode(promoted), saved)

        let deleted = BrowserSyncRecord.delete(
            id: open.id, spaceID: source.spaceID,
            version: .init(logicalClock: 3, deviceID: source.version.deviceID),
            reason: .explicitDelete, at: Date(timeIntervalSince1970: 300))
        let tombstone = try codec.encode(deleted, reusing: cloud)
        XCTAssertEqual((tombstone["schemaVersion"] as? NSNumber)?.intValue, 1)
        XCTAssertNil(tombstone.encryptedValues["payload"])
        XCTAssertEqual(try codec.decode(tombstone), deleted)
    }

    func testNewerServerSchemaCannotBeOverwrittenUsingRestoredSystemFields() throws {
        let source = try makeTabRecord()
        let server = try BrowserCloudRecordCodec().encode(source)
        server["schemaVersion"] = NSNumber(value: 99)
        var fields = BrowserCloudRecordSystemFields()
        fields.update(with: server)
        let restoredFields = try JSONDecoder().decode(
            BrowserCloudRecordSystemFields.self, from: JSONEncoder().encode(fields))
        let base = try XCTUnwrap(restoredFields.record(for: server.recordID))
        XCTAssertThrowsError(try BrowserCloudRecordCodec().encode(source, reusing: base)) { error in
            XCTAssertEqual(error as? BrowserSyncError, .unsupportedSchema(99))
        }
        XCTAssertNil(base.encryptedValues["payload"])
    }

    func testLegacySystemFieldsStillRestoreWithoutSchemaMetadata() throws {
        let source = try makeTabRecord()
        let cloud = try BrowserCloudRecordCodec().encode(source)
        var fields = BrowserCloudRecordSystemFields()
        fields.update(with: cloud)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fields)) as? [String: Any])
        json.removeValue(forKey: "schemaVersionsByName")
        let legacy = try JSONDecoder().decode(
            BrowserCloudRecordSystemFields.self, from: JSONSerialization.data(withJSONObject: json))
        let base = try XCTUnwrap(legacy.record(for: cloud.recordID))
        XCTAssertEqual(
            try BrowserCloudRecordCodec().decode(BrowserCloudRecordCodec().encode(source, reusing: base)), source)
    }

    private func makeTabRecord() throws -> BrowserSyncRecord {
        let spaceID = SpaceID(
            rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        )
        let tab = BrowserSyncTab(
            id: TabID(rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!),
            spaceID: spaceID,
            title: "Example",
            url: try XCTUnwrap(URL(string: "https://example.com")),
            symbol: "globe",
            placement: .current,
            folderID: nil,
            orderToken: "a",
            lastActivatedAt: Date(timeIntervalSince1970: 10)
        )
        return BrowserSyncRecord.save(
            .tab(tab),
            version: BrowserSyncVersion(
                logicalClock: 1,
                deviceID: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
            )
        )
    }
}
