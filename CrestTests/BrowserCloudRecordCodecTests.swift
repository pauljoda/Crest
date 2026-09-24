import CloudKit
import Foundation
import XCTest

@testable import Crest

final class BrowserCloudRecordCodecTests: XCTestCase {
    func testAdditiveCloudPayloadSurvivesCoreEditAndJournalRestart() throws {
        let session = BrowserSession.preview
        var journal = BrowserSyncJournal()
        try journal.stage(session: session)
        let codec = BrowserCloudRecordCodec()
        let records = try journal.records.map { try codec.encode($0) }
        let recordID = BrowserSyncRecordID(kind: .space, value: session.spaces[0].id.rawValue)
        let cloud = try XCTUnwrap(records.first { $0.recordID.recordName == recordID.recordName })
        let original = try XCTUnwrap(cloud.encryptedValues["payload"] as? Data)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var body = try XCTUnwrap(raw["value"] as? [String: Any])
        var branding = try XCTUnwrap(body["branding"] as? [String: Any])
        var crest = try XCTUnwrap(branding["crest"] as? [String: Any])
        raw["futureEnvelope"] = ["values": [true, "retained", NSNull()] as [Any]]
        body["futureSpace"] = NSNumber(value: UInt64.max)
        crest["futureCrest"] = ["enabled": true]
        branding["crest"] = crest
        body["branding"] = branding
        raw["value"] = body
        cloud.encryptedValues["payload"] = try JSONSerialization.data(withJSONObject: raw) as CKRecordValue
        // A newer writer must advance the record version along with its data.
        cloud["logicalClock"] = NSNumber(value: journal.logicalClock + 1)

        var merged = try journal.prepareSession(session, remoteRecords: records.map { try codec.decode($0) }, at: .now)
        merged.spaces[0].name = "Renamed by the older client"
        try journal.stage(session: merged)
        let restored = try BrowserSyncJournal.decodeSnapshot(journal.encodedSnapshot())
        let saved = try XCTUnwrap(restored.records.first { $0.id == recordID })
        let uploaded = try codec.encode(saved)
        let data = try XCTUnwrap(uploaded.encryptedValues["payload"] as? Data)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let value = try XCTUnwrap(result["value"] as? [String: Any])
        let resultBranding = try XCTUnwrap(value["branding"] as? [String: Any])
        let resultCrest = try XCTUnwrap(resultBranding["crest"] as? [String: Any])
        XCTAssertEqual(value["name"] as? String, "Renamed by the older client")
        XCTAssertEqual((value["futureSpace"] as? NSNumber)?.uint64Value, UInt64.max)
        XCTAssertEqual((resultCrest["futureCrest"] as? [String: Bool])?["enabled"], true)
        XCTAssertNotNil(result["futureEnvelope"])
        XCTAssertEqual(try codec.decode(uploaded), saved)
    }

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
        // Build every record kind directly; edits run in the core and are
        // covered there. This test owns the CloudKit payload round trip.
        let renamedID = try XCTUnwrap(session.spaces[0].tabs.first?.id)
        session.spaces[0].tabs[0].customTitle = "Release Notes"
        session.spaces[0].tabs[0].titleModifiedAt = Date(timeIntervalSince1970: 150)
        session.spaces[0].history.append(
            BrowserHistoryEntry(
                url: try XCTUnwrap(URL(string: "https://example.com/history")),
                title: "History",
                firstVisitedAt: Date(timeIntervalSince1970: 100),
                lastVisitedAt: Date(timeIntervalSince1970: 100)
            )
        )
        // A web tab: a closed Start Page is local-only and never syncs.
        let closedIndex = try XCTUnwrap(
            session.spaces[0].tabs.firstIndex {
                $0.placement == .current && $0.id != renamedID && $0.url?.scheme == "https"
            }
        )
        let closed = session.spaces[0].tabs.remove(at: closedIndex)
        session.spaces[0].archivedTabs.append(
            ArchivedTab(tab: closed, archivedAt: Date(timeIntervalSince1970: 200), reason: .closed)
        )
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
        session.spaces = expanded.map { symbol in
            BrowserSpace(
                id: SpaceID(),
                profile: BrowsingProfile(),
                name: symbol.rawValue,
                symbol: "globe",
                accent: .indigo,
                branding: BrowserSpaceBranding(
                    colors: [.ink, .ocean, .gold],
                    iconStyle: .layeredCrest,
                    crest: BrowserSpaceCrest(trim: .none, symbol: symbol)
                ),
                folders: [],
                tabs: []
            )
        }
        var journal = BrowserSyncJournal(
            deviceID: UUID(uuidString: "10000000-0000-0000-0000-000000000009")!
        )
        try journal.stage(session: session, at: Date(timeIntervalSince1970: 300))
        let codec = BrowserCloudRecordCodec()

        let decoded = try journal.records
            .filter { $0.id.kind == .space }
            .map { try codec.decode(codec.encode($0)) }

        XCTAssertEqual(decoded.count, expanded.count)
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

    @MainActor
    func testFullSpaceCustomizationSyncsBetweenStoresAndSurvivesReload() async throws {
        let session = BrowserSession.preview
        let spaceID = session.spaces[0].id
        var senderJournal = BrowserSyncJournal()
        try senderJournal.stage(session: session)
        let senderHarness = try BrowserStoredSessionHarness(session: session, journal: senderJournal)
        let receiverHarness = try BrowserStoredSessionHarness(session: session)
        let sender = senderHarness.store
        let receiver = receiverHarness.store
        let senderCoordinator = try XCTUnwrap(sender.syncCoordinator)
        let receiverCoordinator = try XCTUnwrap(receiver.syncCoordinator)
        let codec = BrowserCloudRecordCodec()
        try receiver.mergeRemoteSyncRecords(
            senderCoordinator.journal.records.map { try codec.decode(codec.encode($0)) })
        try senderCoordinator.markUploaded(senderCoordinator.journal.pendingRecordIDs)

        var branding = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold], bannerPattern: .lozenges,
            bannerStrength: 0.63, readabilityFade: 0.37, themeMode: .gradient,
            gradientAngle: 217, showsTexture: true, iconStyle: .layeredCrest,
            symbolColor: .ember,
            crest: BrowserSpaceCrest(
                backplate: .frenchShield, fieldDivision: .gyronny, ordinary: .pall,
                trim: .beaded, symbol: .direwolf, chargeLayout: .trio,
                backplateColorIndex: 1, secondaryFieldColorIndex: 2, ordinaryColorIndex: 3,
                trimColorIndex: 0, symbolColorIndex: 2, edgeColorIndex: 3,
                palette: [.ember, .gold, .ink, .sand], plateScale: 0.85, edgeWidth: 0.43,
                divisionCount: 6, finish: .sheen, ordinaryWidth: 1.2, trimWeight: 1.3,
                trimDetail: 18, chargeScale: 1.1, chargeOffset: -0.12, chargeWeight: .light,
                startingPresetID: "winter", sheenAngle: 125, sealTeeth: 16,
                showsOutline: true, depth: .lifted),
            folderColorIntensity: 0.71, textColorMode: .light, hasCustomAppearance: true)
        let charges =
            BrowserSpaceCrestSymbol.allCases.map(BrowserSpaceCrestCharge.heraldic)
            + [.system("hammer.fill"), .emoji("🐉"), .monogram("PD", .serif), .none]
        for charge in charges {
            branding.crest.charge = charge
            sender.updateSpaceBranding(branding, in: spaceID)
            await sender.flushPendingSyncPersistence()
            let pending = senderCoordinator.journal.records.filter {
                senderCoordinator.journal.pendingRecordIDs.contains($0.id)
            }
            XCTAssertEqual(pending.map(\.id.kind), [.space])
            try receiver.mergeRemoteSyncRecords(pending.map { try codec.decode(codec.encode($0)) })
            try senderCoordinator.markUploaded(Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0.version) }))

            let expected = try XCTUnwrap(sender.session.space(id: spaceID)?.branding)
            XCTAssertEqual(receiver.session.space(id: spaceID)?.branding, expected, "Charge: \(charge)")
            let reloaded = try JSONDecoder().decode(
                BrowserSession.self, from: JSONEncoder().encode(receiver.session))
            XCTAssertEqual(reloaded.space(id: spaceID)?.branding, expected)
            XCTAssertEqual(reloaded.space(id: spaceID)?.profile.id, session.spaces[0].profile.id)
        }

        // Editing on the receiving device must produce a fresh Space record too.
        var returnedBranding = try XCTUnwrap(receiver.session.space(id: spaceID)?.branding)
        returnedBranding.iconStyle = .simpleSymbol
        returnedBranding.symbolColor = .gold
        returnedBranding.crest.palette = nil
        returnedBranding.crest.charge = .system("leaf.fill")
        receiver.updateSpaceIdentity(spaceID, name: "Garden", symbol: "leaf.fill", accent: .teal)
        receiver.updateSpaceBranding(returnedBranding, in: spaceID)
        await receiver.flushPendingSyncPersistence()
        try sender.mergeRemoteSyncRecords(
            receiverCoordinator.journal.records.map { try codec.decode(codec.encode($0)) })
        XCTAssertEqual(sender.session.space(id: spaceID)?.branding, returnedBranding.normalized())
        XCTAssertEqual(sender.session.space(id: spaceID)?.name, "Garden")
        XCTAssertEqual(sender.session.space(id: spaceID)?.symbol, "leaf.fill")
        XCTAssertEqual(sender.session.space(id: spaceID)?.accent, .teal)
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

        let data = try XCTUnwrap(cloudRecord.encryptedValues["tombstone"] as? Data)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        raw["futureDeletionMetadata"] = ["source": "newer-client"]
        cloudRecord.encryptedValues["tombstone"] = try JSONSerialization.data(withJSONObject: raw) as CKRecordValue
        let withAdditions = try codec.decode(cloudRecord)
        let restored = try JSONDecoder().decode(BrowserSyncRecord.self, from: JSONEncoder().encode(withAdditions))
        let uploaded = try codec.encode(restored)
        let uploadedData = try XCTUnwrap(uploaded.encryptedValues["tombstone"] as? Data)
        let uploadedRaw = try XCTUnwrap(JSONSerialization.jsonObject(with: uploadedData) as? [String: Any])
        XCTAssertEqual((uploadedRaw["futureDeletionMetadata"] as? [String: String])?["source"], "newer-client")
        XCTAssertEqual(restored.tombstone, source.tombstone)
        XCTAssertNil(restored.payload)
    }

    func testReviewZonesCannotReadOrReuseProductionRecords() throws {
        let source = try makeTabRecord()
        let production = BrowserCloudRecordCodec()
        let review = BrowserCloudRecordCodec(zoneName: "CrestReview-test")
        let record = try review.encode(source)
        XCTAssertEqual(record.recordID.zoneID, review.recordZoneID)
        XCTAssertEqual((record["space"] as? CKRecord.Reference)?.recordID.zoneID, review.recordZoneID)
        XCTAssertEqual(try review.decode(record), source)
        XCTAssertThrowsError(try production.decode(record))
        let liveRecord = try production.encode(source)
        XCTAssertThrowsError(try review.decode(liveRecord))
        XCTAssertThrowsError(try review.encode(source, reusing: liveRecord))
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
