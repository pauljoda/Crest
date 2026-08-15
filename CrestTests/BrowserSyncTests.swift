import Foundation
import XCTest

@testable import Crest

final class BrowserSyncTests: XCTestCase {
    func testJournalPayloadIsAPrivacyAllowlistRatherThanAnEncodedSession() throws {
        var session = BrowserSession.preview
        session.spaces[0].credentialPreferences = BrowserCredentialPreferences(
            syncsCrestPasswordsWithICloud: false,
            alsoOffersSaveToSystemPasswords: true
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(1))

        try journal.stage(session: session, at: fixedDate(100))

        let data = try JSONEncoder().encode(journal)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("selectedSpaceID"))
        XCTAssertFalse(json.contains("selectedTabID"))
        XCTAssertFalse(json.contains("credentialPreferences"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("cookie"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("serviceWorker"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("backForward"))
        XCTAssertEqual(
            journal.activeRecords.filter { $0.id.kind == .space }.count,
            session.spaces.count
        )
    }

    func testUnchangedRestageDoesNotAdvanceClockOrCreatePendingWork() throws {
        let session = BrowserSession.preview
        var journal = BrowserSyncJournal(deviceID: fixedUUID(2))
        try journal.stage(session: session, at: fixedDate(100))
        journal.markUploaded(journal.pendingRecordIDs)
        let clock = journal.logicalClock

        try journal.stage(session: session, at: fixedDate(200))

        XCTAssertEqual(journal.logicalClock, clock)
        XCTAssertTrue(journal.pendingRecordIDs.isEmpty)
    }

    func testFractionalReorderStagesOnlyTheMovedTab() throws {
        var session = currentTabSession(count: 4)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(220))
        try journal.stage(session: session, at: fixedDate(100))
        journal.markUploaded(journal.pendingRecordIDs)
        let before = tabOrderTokens(in: journal)
        let moved = session.spaces[0].tabs.removeLast()
        session.spaces[0].tabs.insert(moved, at: 1)

        try journal.stage(session: session, at: fixedDate(200))

        let movedRecordID = BrowserSyncRecordID(
            kind: .tab,
            value: moved.id.rawValue
        )
        XCTAssertEqual(journal.pendingRecordIDs, [movedRecordID])
        let after = tabOrderTokens(in: journal)
        XCTAssertNotEqual(after[moved.id], before[moved.id])
        for tab in session.spaces[0].tabs where tab.id != moved.id {
            XCTAssertEqual(after[tab.id], before[tab.id])
        }
        let materialized = try journal.materializedSession(
            applyingTo: session
        )
        XCTAssertEqual(
            materialized.selectedSpace?.tabs.map(\.id),
            session.selectedSpace?.tabs.map(\.id)
        )
    }

    func testFractionalInsertionDoesNotRewriteExistingSiblings() throws {
        var session = currentTabSession(count: 3)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(221))
        try journal.stage(session: session, at: fixedDate(100))
        journal.markUploaded(journal.pendingRecordIDs)
        let before = tabOrderTokens(in: journal)
        let inserted = BrowserTab(
            id: TabID(rawValue: fixedUUID(722)),
            title: "Inserted",
            url: URL(string: "https://example.com/inserted"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: fixedDate(200)
        )
        session.spaces[0].tabs.insert(inserted, at: 1)

        try journal.stage(session: session, at: fixedDate(200))

        let insertedRecordID = BrowserSyncRecordID(
            kind: .tab,
            value: inserted.id.rawValue
        )
        XCTAssertEqual(journal.pendingRecordIDs, [insertedRecordID])
        let after = tabOrderTokens(in: journal)
        for (id, token) in before {
            XCTAssertEqual(after[id], token)
        }
        let firstToken = try XCTUnwrap(after[session.spaces[0].tabs[0].id])
        let insertedToken = try XCTUnwrap(after[inserted.id])
        let secondToken = try XCTUnwrap(after[session.spaces[0].tabs[2].id])
        XCTAssertLessThan(firstToken, insertedToken)
        XCTAssertLessThan(insertedToken, secondToken)
    }

    func testFractionalOrderingCompactsAfterGapExhaustionWithoutGrowingTokens() throws {
        var session = currentTabSession(count: 2)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(222))
        try journal.stage(session: session, at: fixedDate(100))
        journal.markUploaded(journal.pendingRecordIDs)
        var observedCompaction = false

        for index in 0..<80 {
            let tab = BrowserTab(
                id: TabID(rawValue: fixedUUID(800 + index)),
                title: "Front \(index)",
                url: URL(string: "https://example.com/front/\(index)"),
                symbol: "globe",
                placement: .current,
                lastActivatedAt: fixedDate(TimeInterval(300 + index))
            )
            session.spaces[0].tabs.insert(tab, at: 0)
            try journal.stage(
                session: session,
                at: fixedDate(TimeInterval(300 + index))
            )
            observedCompaction =
                observedCompaction
                || journal.pendingRecordIDs.count > 1
            journal.markUploaded(journal.pendingRecordIDs)
        }

        XCTAssertTrue(observedCompaction)
        let tokens = tabOrderTokens(in: journal)
        XCTAssertEqual(tokens.count, session.spaces[0].tabs.count)
        XCTAssertTrue(
            tokens.values.allSatisfy {
                $0.utf8.count == BrowserSyncOrderTokenAllocator.encodedWidth
                    && BrowserSyncOrderTokenAllocator.isValidEncodedToken($0)
            })
        let materialized = try journal.materializedSession(
            applyingTo: session
        )
        XCTAssertEqual(
            materialized.selectedSpace?.tabs.map(\.id),
            session.selectedSpace?.tabs.map(\.id)
        )
    }

    func testConcurrentFractionalMovesConvergeWithoutSiblingRewrites() throws {
        let base = currentTabSession(count: 5)
        var first = BrowserSyncJournal(deviceID: fixedUUID(223))
        var second = BrowserSyncJournal(deviceID: fixedUUID(224))
        try first.stage(session: base, at: fixedDate(100))
        try second.merge(first.records)
        first.markUploaded(first.pendingRecordIDs)

        var firstEdit = base
        let firstMoved = firstEdit.spaces[0].tabs.removeLast()
        firstEdit.spaces[0].tabs.insert(firstMoved, at: 1)
        try first.stage(session: firstEdit, at: fixedDate(200))

        var secondEdit = base
        let secondMoved = secondEdit.spaces[0].tabs.removeFirst()
        secondEdit.spaces[0].tabs.insert(secondMoved, at: 3)
        try second.stage(session: secondEdit, at: fixedDate(200))

        let firstRecords = first.records
        let secondRecords = second.records
        try first.merge(secondRecords)
        try second.merge(firstRecords)

        XCTAssertEqual(first.records, second.records)
        let firstResult = try first.materializedSession(applyingTo: base)
        let secondResult = try second.materializedSession(applyingTo: base)
        XCTAssertEqual(
            firstResult.selectedSpace?.tabs.map(\.id),
            secondResult.selectedSpace?.tabs.map(\.id)
        )
    }

    func testHostileOrderTokensFailClosed() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let invalidSpace = BrowserSyncSpace(
            id: space.id,
            profileID: space.profile.id,
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            orderToken: String(repeating: "f", count: 17)
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(225))

        XCTAssertThrowsError(
            try journal.merge([
                BrowserSyncRecord.save(
                    .space(invalidSpace),
                    version: BrowserSyncVersion(
                        logicalClock: 1,
                        deviceID: fixedUUID(226)
                    )
                )
            ])
        ) { error in
            XCTAssertEqual(
                error as? BrowserSyncError,
                .invalidField("space.orderToken")
            )
        }
    }

    func testLegacyOrderTokensCanonicalizeWithoutASchemaMigration() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(228))
        try journal.merge([
            spaceRecord(space, clock: 1),
            BrowserSyncRecord.save(
                .tab(syncTab(tab, spaceID: space.id)),
                version: BrowserSyncVersion(
                    logicalClock: 2,
                    deviceID: fixedUUID(229)
                )
            ),
        ])

        try journal.stage(session: session, at: fixedDate(200))

        XCTAssertEqual(
            journal.schemaVersion,
            BrowserSyncJournal.currentSchemaVersion
        )
        XCTAssertEqual(
            journal.pendingRecordIDs,
            [
                BrowserSyncRecordID(kind: .space, value: space.id.rawValue),
                BrowserSyncRecordID(kind: .tab, value: tab.id.rawValue),
            ]
        )
        let tokens = journal.records.compactMap { record -> String? in
            switch record.payload {
            case .space(let space): space.orderToken
            case .tab(let tab): tab.orderToken
            default: nil
            }
        }
        XCTAssertEqual(tokens.count, 2)
        XCTAssertTrue(
            tokens.allSatisfy {
                $0.utf8.count == BrowserSyncOrderTokenAllocator.encodedWidth
                    && BrowserSyncOrderTokenAllocator.isValidEncodedToken($0)
            })
        let materialized = try journal.materializedSession(
            applyingTo: session
        )
        var repairedSession = session
        repairedSession.repairRuntimeIntegrity()
        XCTAssertEqual(materialized, repairedSession)
    }

    func testDuplicateSessionIdentitiesFailClosedDuringFractionalProjection() throws {
        var session = currentTabSession(count: 2)
        let first = session.spaces[0].tabs[0]
        session.spaces[0].tabs[1] = BrowserTab(
            id: first.id,
            title: "Duplicate",
            url: URL(string: "https://example.com/duplicate"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: fixedDate(200)
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(227))
        let duplicateRecordName = BrowserSyncRecordID(
            kind: .tab,
            value: first.id.rawValue
        ).recordName

        XCTAssertThrowsError(
            try journal.stage(
                session: session,
                at: fixedDate(200)
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserSyncError,
                .duplicateRecord(duplicateRecordName)
            )
        }
    }

    func testSpaceBrowsingPreferencesProjectAndMaterializeWithTheSpaceRecord() throws {
        var session = oneSpaceSession()
        let preferences = BrowserSpaceBrowsingPreferences(
            searchProvider: .brave,
            currentTabCleanupPolicy: .after7Days
        )
        session.spaces[0].browsingPreferences = preferences
        var journal = BrowserSyncJournal(deviceID: fixedUUID(210))

        try journal.stage(session: session, at: fixedDate(100))
        var local = session
        local.spaces[0].browsingPreferences = .default
        let materialized = try journal.materializedSession(applyingTo: local)

        XCTAssertEqual(materialized.selectedSpace?.browsingPreferences, preferences)
    }

    func testSpaceBrandingProjectsAndMaterializesWithTheSpaceRecord() throws {
        var session = oneSpaceSession()
        let branding = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            bannerPattern: .quartered,
            bannerStrength: 0.48,
            readabilityFade: 0.57,
            themeMode: .gradient,
            gradientAngle: 226,
            showsTexture: true,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(
                backplate: .hexagon,
                fieldDivision: .perBend,
                ordinary: .cross,
                trim: .doubleRing,
                symbol: .bird,
                chargeLayout: .trio,
                backplateColorIndex: 1,
                secondaryFieldColorIndex: 0,
                ordinaryColorIndex: 2,
                trimColorIndex: 2,
                symbolColorIndex: 0
            )
        )
        session.spaces[0].branding = branding
        var journal = BrowserSyncJournal(deviceID: fixedUUID(211))

        try journal.stage(session: session, at: fixedDate(100))
        var stagedBranding: BrowserSpaceBranding?
        for record in journal.records {
            if case .space(let space)? = record.payload {
                stagedBranding = space.branding
                break
            }
        }
        XCTAssertEqual(stagedBranding, branding)
        var local = session
        local.spaces[0].branding = .legacy(
            accent: local.spaces[0].accent,
            symbol: local.spaces[0].symbol
        )
        let materialized = try journal.materializedSession(applyingTo: local)

        XCTAssertEqual(materialized.selectedSpace?.branding, branding)
    }

    func testConcurrentCrestEditAndCloudTabAdditionReconcileWithoutDatasetConflict() throws {
        let base = oneSpaceSession()
        var mac = BrowserSyncJournal(deviceID: fixedUUID(212))
        var phone = BrowserSyncJournal(deviceID: fixedUUID(213))
        try mac.stage(session: base, at: fixedDate(100))
        try phone.merge(mac.records)
        mac.markUploaded(mac.pendingRecordIDs)

        var macEdit = base
        macEdit.spaces[0].branding = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            bannerPattern: .diagonal,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(
                backplate: .shield,
                fieldDivision: .perBend,
                ordinary: .bend,
                trim: .laurel,
                symbol: .hammer,
                chargeLayout: .trio
            )
        )
        try mac.stage(session: macEdit, at: fixedDate(200))

        var phoneEdit = base
        let cloudTab = BrowserTab.startPage()
        phoneEdit.spaces[0].tabs.append(cloudTab)
        try phone.stage(session: phoneEdit, at: fixedDate(200))

        let macRecords = mac.records
        let phoneRecords = phone.records
        try mac.merge(phoneRecords)
        try phone.merge(macRecords)

        XCTAssertEqual(mac.records, phone.records)
        let reconciled = try mac.materializedSession(applyingTo: base)
        XCTAssertEqual(reconciled.spaces[0].branding, macEdit.spaces[0].branding)
        XCTAssertTrue(reconciled.spaces[0].tabs.contains { $0.id == cloudTab.id })
    }

    func testSavedTabsExpansionProjectsAndMaterializesWithinItsSpace() throws {
        var session = oneSpaceSession()
        let modifiedAt = fixedDate(350)
        session.spaces[0].isSavedTabsExpanded = false
        session.spaces[0].savedTabsExpansionModifiedAt = modifiedAt
        var journal = BrowserSyncJournal(deviceID: fixedUUID(239))

        try journal.stage(session: session, at: fixedDate(400))
        let projectedSpaces: [BrowserSyncSpace] = journal.records.compactMap {
            record -> BrowserSyncSpace? in
            guard case .space(let space)? = record.payload else { return nil }
            return space
        }
        let projected = try XCTUnwrap(projectedSpaces.first)
        var local = session
        local.spaces[0].isSavedTabsExpanded = true
        local.spaces[0].savedTabsExpansionModifiedAt = nil
        let materialized = try journal.materializedSession(applyingTo: local)

        XCTAssertFalse(projected.isSavedTabsExpanded)
        XCTAssertEqual(projected.savedTabsExpansionModifiedAt, modifiedAt)
        XCTAssertEqual(materialized.selectedSpace?.isSavedTabsExpanded, false)
        XCTAssertEqual(
            materialized.selectedSpace?.savedTabsExpansionModifiedAt,
            modifiedAt
        )
    }

    func testNestedFoldersProjectAndMaterializeInSiblingOrder() throws {
        var session = oneSpaceSession()
        let root = SavedFolder(
            id: FolderID(rawValue: fixedUUID(240)),
            title: "Projects",
            symbol: "folder"
        )
        let child = SavedFolder(
            id: FolderID(rawValue: fixedUUID(241)),
            title: "Crest",
            symbol: "folder.fill",
            color: BrowserSpaceBrandColor(red: 0.18, green: 0.42, blue: 0.72),
            parentID: root.id,
            isCollapsed: true,
            collapseModifiedAt: fixedDate(90)
        )
        let sibling = SavedFolder(
            id: FolderID(rawValue: fixedUUID(242)),
            title: "Reading",
            symbol: "books.vertical"
        )
        session.spaces[0].folders = [root, child, sibling]
        var journal = BrowserSyncJournal(deviceID: fixedUUID(243))

        try journal.stage(session: session, at: fixedDate(100))
        let projectedFolders: [BrowserSyncFolder] = journal.records.compactMap { record in
            guard case .folder(let folder)? = record.payload,
                folder.id == child.id
            else { return nil }
            return folder
        }
        let projectedChild = try XCTUnwrap(projectedFolders.first)
        let materialized = try journal.materializedSession(applyingTo: session)
        let folders = try XCTUnwrap(materialized.selectedSpace?.folders)

        XCTAssertEqual(projectedChild.parentID, root.id)
        XCTAssertEqual(projectedChild.color, child.color)
        XCTAssertTrue(projectedChild.isCollapsed)
        XCTAssertEqual(projectedChild.collapseModifiedAt, fixedDate(90))
        XCTAssertEqual(folders.map(\.id), [root.id, child.id, sibling.id])
        XCTAssertEqual(folders[1].parentID, root.id)
        XCTAssertEqual(folders[1].color, child.color)
        XCTAssertTrue(folders[1].isCollapsed)
        XCTAssertEqual(folders[1].collapseModifiedAt, fixedDate(90))
        XCTAssertTrue(BrowserFolderTree(folders: folders).isValid)
    }

    func testLegacySyncFolderWithoutCollapseStateDefaultsToExpanded() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let source = BrowserSyncFolder(
            id: FolderID(rawValue: fixedUUID(248)),
            spaceID: space.id,
            title: "Legacy",
            symbol: "folder",
            orderToken: "a"
        )
        let encoded = try JSONEncoder().encode(source)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "isCollapsed")
        object.removeValue(forKey: "collapseModifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            BrowserSyncFolder.self,
            from: legacyData
        )

        XCTAssertFalse(decoded.isCollapsed)
        XCTAssertNil(decoded.collapseModifiedAt)
    }

    func testMaterializationRejectsCyclicFolderHierarchy() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let firstID = FolderID(rawValue: fixedUUID(244))
        let secondID = FolderID(rawValue: fixedUUID(245))
        var journal = BrowserSyncJournal(deviceID: fixedUUID(246))
        try journal.merge([
            spaceRecord(space, clock: 1),
            BrowserSyncRecord.save(
                .folder(
                    BrowserSyncFolder(
                        id: firstID,
                        spaceID: space.id,
                        title: "First",
                        symbol: "folder",
                        parentID: secondID,
                        orderToken: "a"
                    )),
                version: BrowserSyncVersion(logicalClock: 2, deviceID: fixedUUID(247))
            ),
            BrowserSyncRecord.save(
                .folder(
                    BrowserSyncFolder(
                        id: secondID,
                        spaceID: space.id,
                        title: "Second",
                        symbol: "folder",
                        parentID: firstID,
                        orderToken: "b"
                    )),
                version: BrowserSyncVersion(logicalClock: 3, deviceID: fixedUUID(247))
            ),
        ])

        XCTAssertThrowsError(try journal.materializedSession(applyingTo: session)) { error in
            XCTAssertEqual(error as? BrowserSyncError, .invalidFolderHierarchy(space.id))
        }
    }

    func testLegacySyncSpaceWithoutBrowsingPreferencesUsesDefaults() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let syncSpace = BrowserSyncSpace(
            id: space.id,
            profileID: space.profile.id,
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            orderToken: "a"
        )
        let encoded = try JSONEncoder().encode(syncSpace)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "browsingPreferences")
        object.removeValue(forKey: "isSavedTabsExpanded")
        object.removeValue(forKey: "savedTabsExpansionModifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserSyncSpace.self, from: legacyData)

        XCTAssertEqual(decoded.browsingPreferences, .default)
        XCTAssertTrue(decoded.isSavedTabsExpanded)
        XCTAssertNil(decoded.savedTabsExpansionModifiedAt)
    }

    func testLegacySyncSpaceWithoutBrandingUsesItsAccentAndSymbol() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let syncSpace = BrowserSyncSpace(
            id: space.id,
            profileID: space.profile.id,
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            orderToken: "a"
        )
        let encoded = try JSONEncoder().encode(syncSpace)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "branding")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserSyncSpace.self, from: legacyData)

        XCTAssertEqual(decoded.branding, .legacy(accent: space.accent, symbol: space.symbol))
    }

    func testStaleUploadAcknowledgementCannotClearANewerLocalEdit() throws {
        var session = oneSpaceSession()
        var journal = BrowserSyncJournal(deviceID: fixedUUID(201))
        try journal.stage(session: session, at: fixedDate(100))
        let spaceRecordID = BrowserSyncRecordID(
            kind: .space,
            value: session.selectedSpaceID.rawValue
        )
        let uploadedVersion = try XCTUnwrap(
            journal.records.first { $0.id == spaceRecordID }?.version
        )
        session.spaces[0].name = "Newer local rename"
        try journal.stage(session: session, at: fixedDate(200))

        journal.markUploaded([spaceRecordID: uploadedVersion])

        XCTAssertTrue(journal.pendingRecordIDs.contains(spaceRecordID))
        let currentVersion = try XCTUnwrap(
            journal.records.first { $0.id == spaceRecordID }?.version
        )
        journal.markUploaded([spaceRecordID: currentVersion])
        XCTAssertFalse(journal.pendingRecordIDs.contains(spaceRecordID))
    }

    func testHostileMaximumLogicalClockFailsClosedInsteadOfOverflowing() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let remoteSpace = BrowserSyncSpace(
            id: space.id,
            profileID: space.profile.id,
            name: "Remote name",
            symbol: space.symbol,
            accent: space.accent,
            orderToken: "a"
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(202))
        try journal.merge([
            BrowserSyncRecord.save(
                .space(remoteSpace),
                version: BrowserSyncVersion(
                    logicalClock: UInt64.max,
                    deviceID: fixedUUID(203)
                )
            )
        ])
        XCTAssertThrowsError(try journal.stage(session: session, at: fixedDate(200))) { error in
            XCTAssertEqual(error as? BrowserSyncError, .logicalClockExhausted)
        }
    }

    func testRemovingAProjectedRecordCreatesADurableTombstone() throws {
        var session = oneSpaceSession()
        let removedTabID = try XCTUnwrap(session.selectedSpace?.tabs.first?.id)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(3))
        try journal.stage(session: session, at: fixedDate(100))
        journal.markUploaded(journal.pendingRecordIDs)
        session.spaces[0].tabs.removeAll { $0.id == removedTabID }

        try journal.stage(session: session, at: fixedDate(200))

        let record = try XCTUnwrap(
            journal.records.first {
                $0.id == BrowserSyncRecordID(kind: .tab, value: removedTabID.rawValue)
            })
        XCTAssertNil(record.payload)
        XCTAssertEqual(record.tombstone?.reason, .explicitDelete)
        XCTAssertEqual(record.tombstone?.deletedAt, fixedDate(200))
        XCTAssertTrue(journal.pendingRecordIDs.contains(record.id))
    }

    func testExplicitDeleteWinsAgainstANewerEdit() throws {
        let fixture = oneSpaceSession()
        let space = try XCTUnwrap(fixture.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let payload = syncTab(tab, spaceID: space.id)
        let recordID = BrowserSyncRecordID(kind: .tab, value: tab.id.rawValue)
        let save = BrowserSyncRecord.save(
            .tab(payload),
            version: BrowserSyncVersion(logicalClock: 20, deviceID: fixedUUID(4))
        )
        let deletion = BrowserSyncRecord.delete(
            id: recordID,
            spaceID: space.id,
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(5)),
            reason: .explicitDelete,
            at: fixedDate(200)
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(6))

        try journal.merge([save])
        try journal.merge([deletion])

        let resolved = try XCTUnwrap(journal.records.first { $0.id == recordID })
        XCTAssertNil(resolved.payload)
        XCTAssertEqual(resolved.tombstone?.reason, .explicitDelete)
    }

    func testConcurrentPlacementMergeKeepsTheMoreDurableArcPlacement() throws {
        let fixture = oneSpaceSession()
        let space = try XCTUnwrap(fixture.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        var current = syncTab(tab, spaceID: space.id)
        current.placement = .current
        var pinned = current
        pinned.placement = .pinned
        let olderPinned = BrowserSyncRecord.save(
            .tab(pinned),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(7))
        )
        let newerCurrent = BrowserSyncRecord.save(
            .tab(current),
            version: BrowserSyncVersion(logicalClock: 20, deviceID: fixedUUID(8))
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(9))

        try journal.merge([olderPinned])
        try journal.merge([newerCurrent])

        let resolved = try XCTUnwrap(journal.records.first { $0.id.kind == .tab })
        guard case .tab(let resolvedTab)? = resolved.payload else {
            return XCTFail("Expected a tab payload")
        }
        XCTAssertEqual(resolvedTab.placement, .pinned)
        XCTAssertTrue(journal.pendingRecordIDs.contains(resolved.id))
    }

    func testLaterSavedTabsExpansionWinsAgainstAHigherStaleLogicalClock() throws {
        let fixture = oneSpaceSession()
        let space = try XCTUnwrap(fixture.selectedSpace)
        let stale = BrowserSyncSpace(
            id: space.id,
            profileID: space.profile.id,
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            isSavedTabsExpanded: true,
            savedTabsExpansionModifiedAt: fixedDate(200),
            orderToken: "a"
        )
        var latest = stale
        latest.isSavedTabsExpanded = false
        latest.savedTabsExpansionModifiedAt = fixedDate(300)
        let staleRecord = BrowserSyncRecord.save(
            .space(stale),
            version: BrowserSyncVersion(logicalClock: 100, deviceID: fixedUUID(940))
        )
        let latestRecord = BrowserSyncRecord.save(
            .space(latest),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(941))
        )
        var first = BrowserSyncJournal(deviceID: fixedUUID(942))
        var second = BrowserSyncJournal(deviceID: fixedUUID(943))

        try first.merge([staleRecord])
        try first.merge([latestRecord])
        try second.merge([latestRecord])
        try second.merge([staleRecord])

        XCTAssertEqual(first.records, second.records)
        let resolved = try XCTUnwrap(first.records.first { $0.id.kind == .space })
        guard case .space(let resolvedSpace)? = resolved.payload else {
            return XCTFail("Expected a Space payload")
        }
        XCTAssertFalse(resolvedSpace.isSavedTabsExpanded)
        XCTAssertEqual(resolvedSpace.savedTabsExpansionModifiedAt, fixedDate(300))
    }

    func testLaterFolderDisclosureWinsAgainstAHigherStaleLogicalClock() throws {
        let fixture = oneSpaceSession()
        let space = try XCTUnwrap(fixture.selectedSpace)
        let folderID = FolderID(rawValue: fixedUUID(944))
        let stale = BrowserSyncFolder(
            id: folderID,
            spaceID: space.id,
            title: "Projects",
            symbol: "folder",
            isCollapsed: false,
            collapseModifiedAt: fixedDate(200),
            orderToken: "a"
        )
        var latest = stale
        latest.isCollapsed = true
        latest.collapseModifiedAt = fixedDate(300)
        let staleRecord = BrowserSyncRecord.save(
            .folder(stale),
            version: BrowserSyncVersion(logicalClock: 100, deviceID: fixedUUID(945))
        )
        let latestRecord = BrowserSyncRecord.save(
            .folder(latest),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(946))
        )
        var first = BrowserSyncJournal(deviceID: fixedUUID(947))
        var second = BrowserSyncJournal(deviceID: fixedUUID(948))

        try first.merge([staleRecord])
        try first.merge([latestRecord])
        try second.merge([latestRecord])
        try second.merge([staleRecord])

        XCTAssertEqual(first.records, second.records)
        let resolved = try XCTUnwrap(first.records.first { $0.id.kind == .folder })
        guard case .folder(let resolvedFolder)? = resolved.payload else {
            return XCTFail("Expected a folder payload")
        }
        XCTAssertTrue(resolvedFolder.isCollapsed)
        XCTAssertEqual(resolvedFolder.collapseModifiedAt, fixedDate(300))
    }

    func testLaterTabPositionChangeWinsAgainstAHigherStaleLogicalClock() throws {
        let fixture = oneSpaceSession()
        let space = try XCTUnwrap(fixture.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        var stale = syncTab(tab, spaceID: space.id)
        stale.placement = .pinned
        stale.orderToken = "b"
        stale.positionModifiedAt = fixedDate(200)
        var latest = stale
        latest.placement = .current
        latest.orderToken = "a"
        latest.positionModifiedAt = fixedDate(300)
        let staleRecord = BrowserSyncRecord.save(
            .tab(stale),
            version: BrowserSyncVersion(logicalClock: 100, deviceID: fixedUUID(93))
        )
        let latestRecord = BrowserSyncRecord.save(
            .tab(latest),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(94))
        )
        var first = BrowserSyncJournal(deviceID: fixedUUID(95))
        var second = BrowserSyncJournal(deviceID: fixedUUID(96))

        try first.merge([staleRecord])
        try first.merge([latestRecord])
        try second.merge([latestRecord])
        try second.merge([staleRecord])

        XCTAssertEqual(first.records, second.records)
        let resolved = try XCTUnwrap(first.records.first { $0.id.kind == .tab })
        guard case .tab(let resolvedTab)? = resolved.payload else {
            return XCTFail("Expected a tab payload")
        }
        XCTAssertEqual(resolvedTab.placement, .current)
        XCTAssertEqual(resolvedTab.orderToken, "a")
        XCTAssertEqual(resolvedTab.positionModifiedAt, fixedDate(300))
    }

    func testLegacySyncTabWithoutPositionTimestampStillDecodes() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let encoded = try JSONEncoder().encode(syncTab(tab, spaceID: space.id))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "positionModifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserSyncTab.self, from: legacyData)

        XCTAssertNil(decoded.positionModifiedAt)
    }

    func testLaterTabRenameWinsAgainstAHigherStaleLogicalClock() throws {
        let fixture = oneSpaceSession()
        let space = try XCTUnwrap(fixture.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        var stale = syncTab(tab, spaceID: space.id)
        stale.customTitle = "Stale Name"
        stale.titleModifiedAt = fixedDate(200)
        var latest = stale
        latest.customTitle = "Latest Name"
        latest.titleModifiedAt = fixedDate(300)
        let staleRecord = BrowserSyncRecord.save(
            .tab(stale),
            version: BrowserSyncVersion(logicalClock: 100, deviceID: fixedUUID(97))
        )
        let latestRecord = BrowserSyncRecord.save(
            .tab(latest),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(98))
        )
        var first = BrowserSyncJournal(deviceID: fixedUUID(105))
        var second = BrowserSyncJournal(deviceID: fixedUUID(106))

        try first.merge([staleRecord])
        try first.merge([latestRecord])
        try second.merge([latestRecord])
        try second.merge([staleRecord])

        XCTAssertEqual(first.records, second.records)
        let resolved = try XCTUnwrap(first.records.first { $0.id.kind == .tab })
        guard case .tab(let resolvedTab)? = resolved.payload else {
            return XCTFail("Expected a tab payload")
        }
        XCTAssertEqual(resolvedTab.customTitle, "Latest Name")
        XCTAssertEqual(resolvedTab.titleModifiedAt, fixedDate(300))
    }

    func testLaterClearedRenameBeatsAnEarlierRenameFromAnotherDevice() throws {
        let fixture = oneSpaceSession()
        let space = try XCTUnwrap(fixture.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        var renamed = syncTab(tab, spaceID: space.id)
        renamed.customTitle = "Stale Name"
        renamed.titleModifiedAt = fixedDate(200)
        var cleared = renamed
        cleared.customTitle = nil
        cleared.titleModifiedAt = fixedDate(400)
        let renamedRecord = BrowserSyncRecord.save(
            .tab(renamed),
            version: BrowserSyncVersion(logicalClock: 100, deviceID: fixedUUID(107))
        )
        let clearedRecord = BrowserSyncRecord.save(
            .tab(cleared),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(108))
        )
        var first = BrowserSyncJournal(deviceID: fixedUUID(109))
        var second = BrowserSyncJournal(deviceID: fixedUUID(110))

        try first.merge([renamedRecord])
        try first.merge([clearedRecord])
        try second.merge([clearedRecord])
        try second.merge([renamedRecord])

        XCTAssertEqual(first.records, second.records)
        let resolved = try XCTUnwrap(first.records.first { $0.id.kind == .tab })
        guard case .tab(let resolvedTab)? = resolved.payload else {
            return XCTFail("Expected a tab payload")
        }
        XCTAssertNil(resolvedTab.customTitle)
        XCTAssertEqual(resolvedTab.titleModifiedAt, fixedDate(400))
    }

    func testRenamedTabProjectsAndMaterializesWithinItsOwnSpace() throws {
        var session = oneSpaceSession()
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let tabID = try XCTUnwrap(session.selectedSpace?.tabs.first?.id)
        XCTAssertTrue(
            session.setTabCustomTitle(
                "Release Notes",
                tabID: tabID,
                in: spaceID,
                at: fixedDate(200)
            )
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(111))

        try journal.stage(session: session, at: fixedDate(300))
        let materialized = try journal.materializedSession(applyingTo: session)

        let projected = try XCTUnwrap(
            journal.records.compactMap { record -> BrowserSyncTab? in
                guard case .tab(let tab)? = record.payload else { return nil }
                return tab
            }.first)
        XCTAssertEqual(projected.spaceID, spaceID)
        XCTAssertEqual(projected.customTitle, "Release Notes")
        XCTAssertEqual(projected.titleModifiedAt, fixedDate(200))
        let tab = try XCTUnwrap(
            materialized.space(id: spaceID)?.tabs.first(where: { $0.id == tabID })
        )
        XCTAssertEqual(tab.customTitle, "Release Notes")
        XCTAssertEqual(tab.titleModifiedAt, fixedDate(200))
        XCTAssertEqual(tab.displayTitle, "Release Notes")
        XCTAssertEqual(tab.title, "Example")
    }

    func testKeepLoadedStateProjectsAndMaterializesWithItsTab() throws {
        var session = oneSpaceSession()
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let tabID = try XCTUnwrap(session.selectedSpace?.tabs.first?.id)
        XCTAssertTrue(
            session.setTabKeepsPageLoaded(
                true,
                tabID: tabID,
                in: spaceID
            )
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(112))

        try journal.stage(session: session, at: fixedDate(300))
        let materialized = try journal.materializedSession(applyingTo: session)

        let projected = try XCTUnwrap(
            journal.records.compactMap { record -> BrowserSyncTab? in
                guard case .tab(let tab)? = record.payload else { return nil }
                return tab
            }.first
        )
        XCTAssertTrue(projected.keepsPageLoaded)
        XCTAssertEqual(
            materialized.space(id: spaceID)?.tabs.first(where: { $0.id == tabID })?
                .keepsPageLoaded,
            true
        )
    }

    func testLegacySyncTabWithoutRenameFieldsStillDecodes() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        var renamed = syncTab(tab, spaceID: space.id)
        renamed.customTitle = "Release Notes"
        renamed.titleModifiedAt = fixedDate(200)
        let encoded = try JSONEncoder().encode(renamed)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "customTitle")
        object.removeValue(forKey: "titleModifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserSyncTab.self, from: legacyData)

        XCTAssertNil(decoded.customTitle)
        XCTAssertNil(decoded.titleModifiedAt)
        XCTAssertEqual(decoded.title, renamed.title)
    }

    func testLegacySyncTabWithoutKeepLoadedStateDefaultsToAutomaticResidency() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        var kept = syncTab(tab, spaceID: space.id)
        kept.keepsPageLoaded = true
        let encoded = try JSONEncoder().encode(kept)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "keepsPageLoaded")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BrowserSyncTab.self, from: legacyData)

        XCTAssertFalse(decoded.keepsPageLoaded)
    }

    func testSplitGroupMembershipProjectsAndMaterializesAsAContiguousRun() throws {
        let groupID = SplitGroupID(rawValue: fixedUUID(1_120))
        let session = splitGroupSession(memberships: [nil, groupID, groupID, groupID])
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let memberIDs = try XCTUnwrap(session.selectedSpace).tabs.dropFirst().map(\.id)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(1_121))

        try journal.stage(session: session, at: fixedDate(300))
        let materialized = try journal.materializedSession(applyingTo: session)

        let projected = journal.records
            .compactMap { record -> BrowserSyncTab? in
                guard case .tab(let tab)? = record.payload else { return nil }
                return tab
            }
            .sorted { $0.orderToken < $1.orderToken }
        XCTAssertEqual(
            projected.map(\.splitGroupID),
            [nil, groupID, groupID, groupID]
        )
        let space = try XCTUnwrap(materialized.space(id: spaceID))
        XCTAssertEqual(space.tabs.map(\.id), try XCTUnwrap(session.selectedSpace).tabs.map(\.id))
        XCTAssertEqual(
            space.tabs.map(\.splitGroupID),
            [nil, groupID, groupID, groupID]
        )
        XCTAssertEqual(space.splitGroupMembers(of: groupID).map(\.id), memberIDs)
        XCTAssertEqual(space.splitGroup(containing: try XCTUnwrap(memberIDs.first)), groupID)
        XCTAssertEqual(space.liveSplitGroupIDs, [groupID])
    }

    /// The field-strip mitigation. A device that predates split view re-saves a
    /// tab it merely activated: its record has a fresher logical clock and a
    /// fresher activation, but its encoder never wrote `splitGroupID` and its
    /// save never touched `positionModifiedAt`. Membership rides the position
    /// win-set precisely so the group-aware copy wins the field back.
    func testOldClientActivationCannotStripSplitMembership() throws {
        let groupID = SplitGroupID(rawValue: fixedUUID(1_130))
        let session = splitGroupSession(
            memberships: [groupID, groupID],
            positionModifiedAt: fixedDate(300)
        )
        let memberID = try XCTUnwrap(session.selectedSpace?.tabs.first?.id)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(1_131))
        try journal.stage(session: session, at: fixedDate(300))
        let grouped = try XCTUnwrap(projectedTab(memberID, in: journal))
        XCTAssertEqual(grouped.splitGroupID, groupID)

        var activated = grouped
        activated.positionModifiedAt = fixedDate(100)
        activated.lastActivatedAt = fixedDate(400)
        let stripped = try tabAsAnOlderBuildWroteIt(activated)
        XCTAssertNil(stripped.splitGroupID)
        let groupedRecord = BrowserSyncRecord.save(
            .tab(grouped),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(1_132))
        )
        let strippedRecord = BrowserSyncRecord.save(
            .tab(stripped),
            version: BrowserSyncVersion(logicalClock: 100, deviceID: fixedUUID(1_133))
        )
        var first = BrowserSyncJournal(deviceID: fixedUUID(1_134))
        var second = BrowserSyncJournal(deviceID: fixedUUID(1_135))

        try first.merge([groupedRecord])
        try first.merge([strippedRecord])
        try second.merge([strippedRecord])
        try second.merge([groupedRecord])

        XCTAssertEqual(first.records, second.records)
        let resolved = try XCTUnwrap(first.records.first { $0.id.kind == .tab })
        guard case .tab(let resolvedTab)? = resolved.payload else {
            return XCTFail("Expected a tab payload")
        }
        XCTAssertEqual(resolvedTab.splitGroupID, groupID)
        XCTAssertEqual(resolvedTab.positionModifiedAt, fixedDate(300))
        XCTAssertEqual(resolvedTab.lastActivatedAt, fixedDate(400))
    }

    /// The other side of the same rule. That older device is entitled to move a
    /// tab, and moving a member out of its run is an ungroup however old the
    /// build is, so the position it wins takes membership with it.
    func testOldClientMoveLegitimatelyEndsSplitMembership() throws {
        let groupID = SplitGroupID(rawValue: fixedUUID(1_140))
        let session = splitGroupSession(
            memberships: [groupID, groupID],
            positionModifiedAt: fixedDate(300)
        )
        let memberID = try XCTUnwrap(session.selectedSpace?.tabs.first?.id)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(1_141))
        try journal.stage(session: session, at: fixedDate(300))
        let grouped = try XCTUnwrap(projectedTab(memberID, in: journal))

        var moved = grouped
        moved.orderToken = "ffffffffffffffff"
        moved.positionModifiedAt = fixedDate(500)
        let stripped = try tabAsAnOlderBuildWroteIt(moved)
        let groupedRecord = BrowserSyncRecord.save(
            .tab(grouped),
            version: BrowserSyncVersion(logicalClock: 100, deviceID: fixedUUID(1_142))
        )
        let strippedRecord = BrowserSyncRecord.save(
            .tab(stripped),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(1_143))
        )
        var first = BrowserSyncJournal(deviceID: fixedUUID(1_144))
        var second = BrowserSyncJournal(deviceID: fixedUUID(1_145))

        try first.merge([groupedRecord])
        try first.merge([strippedRecord])
        try second.merge([strippedRecord])
        try second.merge([groupedRecord])

        XCTAssertEqual(first.records, second.records)
        let resolved = try XCTUnwrap(first.records.first { $0.id.kind == .tab })
        guard case .tab(let resolvedTab)? = resolved.payload else {
            return XCTFail("Expected a tab payload")
        }
        XCTAssertNil(resolvedTab.splitGroupID)
        XCTAssertEqual(resolvedTab.orderToken, "ffffffffffffffff")
        XCTAssertEqual(resolvedTab.positionModifiedAt, fixedDate(500))
    }

    /// A record written before position-aware sync carries no
    /// `positionModifiedAt` at all, so neither copy can claim to have cleared
    /// membership. The nil-fallback `folderID` already uses covers that: the
    /// copy that knows the group keeps it.
    func testSplitMembershipSurvivesRecordsWithNoPositionTimestampAtAll() throws {
        let groupID = SplitGroupID(rawValue: fixedUUID(1_180))
        let session = splitGroupSession(memberships: [groupID, groupID])
        let memberID = try XCTUnwrap(session.selectedSpace?.tabs.first?.id)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(1_181))
        try journal.stage(session: session, at: fixedDate(300))
        let grouped = try XCTUnwrap(projectedTab(memberID, in: journal))
        XCTAssertNil(grouped.positionModifiedAt)

        var activated = grouped
        activated.lastActivatedAt = fixedDate(400)
        let stripped = try tabAsAnOlderBuildWroteIt(activated)
        let groupedRecord = BrowserSyncRecord.save(
            .tab(grouped),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(1_182))
        )
        let strippedRecord = BrowserSyncRecord.save(
            .tab(stripped),
            version: BrowserSyncVersion(logicalClock: 100, deviceID: fixedUUID(1_183))
        )
        var first = BrowserSyncJournal(deviceID: fixedUUID(1_184))
        var second = BrowserSyncJournal(deviceID: fixedUUID(1_185))

        try first.merge([groupedRecord])
        try first.merge([strippedRecord])
        try second.merge([strippedRecord])
        try second.merge([groupedRecord])

        XCTAssertEqual(first.records, second.records)
        let resolved = try XCTUnwrap(first.records.first { $0.id.kind == .tab })
        guard case .tab(let resolvedTab)? = resolved.payload else {
            return XCTFail("Expected a tab payload")
        }
        XCTAssertEqual(resolvedTab.splitGroupID, groupID)
        XCTAssertNil(resolvedTab.positionModifiedAt)
    }

    /// Order tokens, not the field, decide who is next to whom. A non-member
    /// landing between two members interrupts the run, and repair answers the
    /// same way every time: the first run keeps the group, the split-off tail
    /// loses it.
    func testAnInterleavedNonMemberClearsOnlyTheSplitOffRun() throws {
        let groupID = SplitGroupID(rawValue: fixedUUID(1_150))
        let session = splitGroupSession(memberships: [groupID, groupID, nil, groupID])
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let tabIDs = try XCTUnwrap(session.selectedSpace).tabs.map(\.id)
        var journal = BrowserSyncJournal(deviceID: fixedUUID(1_151))
        try journal.stage(session: session, at: fixedDate(300))

        let materialized = try journal.materializedSession(applyingTo: session)

        let space = try XCTUnwrap(materialized.space(id: spaceID))
        XCTAssertEqual(space.tabs.map(\.id), tabIDs)
        XCTAssertEqual(
            space.tabs.map(\.splitGroupID),
            [groupID, groupID, nil, nil]
        )
        XCTAssertEqual(space.splitGroupMembers(of: groupID).map(\.id), Array(tabIDs.prefix(2)))
        XCTAssertEqual(space.liveSplitGroupIDs, [groupID])

        let again = try journal.materializedSession(applyingTo: materialized)

        XCTAssertEqual(
            try XCTUnwrap(again.space(id: spaceID)).tabs.map(\.splitGroupID),
            [groupID, groupID, nil, nil]
        )
    }

    /// The singleton regression. A CloudKit batch has no ordering guarantee, so
    /// one member of a three-member group can land alone. Repair has to keep
    /// that lone member's ID — stripping it would re-upload the strip to every
    /// other device — even though nothing renders as a split until the siblings
    /// arrive.
    func testALoneSplitMemberSurvivesUntilItsSiblingsArrive() throws {
        let groupID = SplitGroupID(rawValue: fixedUUID(1_160))
        let cloudSpaceID = SpaceID(rawValue: fixedUUID(1_161))
        let cloudSession = splitGroupSession(
            memberships: [groupID, groupID, groupID],
            spaceID: cloudSpaceID
        )
        let memberIDs = try XCTUnwrap(cloudSession.space(id: cloudSpaceID)).tabs.map(\.id)
        var cloud = BrowserSyncJournal(deviceID: fixedUUID(1_162))
        try cloud.stage(session: cloudSession, at: fixedDate(900))
        let firstMemberRecordID = BrowserSyncRecordID(
            kind: .tab,
            value: try XCTUnwrap(memberIDs.first).rawValue
        )
        let laterMemberRecordIDs = Set(
            memberIDs.dropFirst().map { BrowserSyncRecordID(kind: .tab, value: $0.rawValue) }
        )
        let firstBatch = cloud.records.filter { !laterMemberRecordIDs.contains($0.id) }
        let secondBatch = cloud.records.filter { laterMemberRecordIDs.contains($0.id) }
        let localSession = oneSpaceSession()
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: fixedUUID(1_163)
        )
        try coordinator.stage(session: localSession, at: fixedDate(100))

        let afterOne = try coordinator.merge(
            remoteRecords: firstBatch,
            into: localSession,
            at: fixedDate(1_000)
        )

        let lonely = try XCTUnwrap(afterOne.space(id: cloudSpaceID))
        XCTAssertEqual(lonely.tabs.map(\.splitGroupID), [groupID])
        XCTAssertNil(
            lonely.splitGroup(containing: try XCTUnwrap(memberIDs.first)),
            "A run of one must not present as a split"
        )
        let staged = try XCTUnwrap(
            projectedTab(try XCTUnwrap(memberIDs.first), in: coordinator.journal)
        )
        XCTAssertEqual(
            staged.splitGroupID,
            groupID,
            "Repair stripped a lone member and staged the strip for upload"
        )
        XCTAssertEqual(staged.orderToken, projectedTab(memberIDs[0], in: cloud)?.orderToken)
        XCTAssertNotNil(coordinator.journal.records.first { $0.id == firstMemberRecordID })

        let afterAll = try coordinator.merge(
            remoteRecords: secondBatch,
            into: afterOne,
            at: fixedDate(1_100)
        )

        let reconstituted = try XCTUnwrap(afterAll.space(id: cloudSpaceID))
        XCTAssertEqual(reconstituted.tabs.map(\.id), memberIDs)
        XCTAssertEqual(
            reconstituted.tabs.map(\.splitGroupID),
            [groupID, groupID, groupID]
        )
        XCTAssertEqual(reconstituted.splitGroupMembers(of: groupID).map(\.id), memberIDs)
        XCTAssertEqual(reconstituted.liveSplitGroupIDs, [groupID])
    }

    func testArchivePayloadCarryingSplitMembershipFailsValidation() throws {
        let groupID = SplitGroupID(rawValue: fixedUUID(1_170))
        let session = splitGroupSession(memberships: [groupID, groupID])
        let space = try XCTUnwrap(session.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        var archived = syncTab(tab, spaceID: space.id)
        archived.splitGroupID = groupID

        XCTAssertThrowsError(
            try BrowserSyncPayload.archive(
                BrowserSyncArchive(
                    tab: archived,
                    archivedAt: fixedDate(500),
                    reason: .closed
                )
            ).validate()
        ) { error in
            XCTAssertEqual(error as? BrowserSyncError, .invalidField("archive.tab"))
        }

        // The same record without membership passes, so the rejection belongs to
        // the field rather than to the fixture.
        archived.splitGroupID = nil
        XCTAssertNoThrow(
            try BrowserSyncPayload.archive(
                BrowserSyncArchive(
                    tab: archived,
                    archivedAt: fixedDate(500),
                    reason: .closed
                )
            ).validate()
        )
    }

    func testHistoryMergeRetainsTheFullObservedVisitRange() throws {
        let session = oneSpaceSession()
        let spaceID = try XCTUnwrap(session.selectedSpace?.id)
        let historyID = fixedUUID(10)
        let first = BrowserSyncHistory(
            id: historyID,
            spaceID: spaceID,
            url: try XCTUnwrap(URL(string: "https://example.com")),
            title: "Earlier",
            firstVisitedAt: fixedDate(10),
            lastVisitedAt: fixedDate(20),
            visitCount: 2
        )
        let second = BrowserSyncHistory(
            id: historyID,
            spaceID: spaceID,
            url: try XCTUnwrap(URL(string: "https://example.com")),
            title: "Later",
            firstVisitedAt: fixedDate(15),
            lastVisitedAt: fixedDate(40),
            visitCount: 5
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(11))
        try journal.merge([
            BrowserSyncRecord.save(
                .history(first),
                version: BrowserSyncVersion(logicalClock: 5, deviceID: fixedUUID(12))
            )
        ])

        try journal.merge([
            BrowserSyncRecord.save(
                .history(second),
                version: BrowserSyncVersion(logicalClock: 6, deviceID: fixedUUID(13))
            )
        ])

        let record = try XCTUnwrap(journal.records.first { $0.id.kind == .history })
        guard case .history(let history)? = record.payload else {
            return XCTFail("Expected a history payload")
        }
        XCTAssertEqual(history.title, "Later")
        XCTAssertEqual(history.firstVisitedAt, fixedDate(10))
        XCTAssertEqual(history.lastVisitedAt, fixedDate(40))
        XCTAssertEqual(history.visitCount, 5)
    }

    func testNewerActivationDefeatsStaleAutoCleanupAcrossDevices() throws {
        let local = oneSpaceSession(lastActivatedAt: fixedDate(300))
        let space = try XCTUnwrap(local.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let records = [
            spaceRecord(space, clock: 1),
            BrowserSyncRecord.save(
                .tab(syncTab(tab, spaceID: space.id)),
                version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(14))
            ),
            BrowserSyncRecord.save(
                .archive(
                    BrowserSyncArchive(
                        tab: syncTab(tab, spaceID: space.id),
                        archivedAt: fixedDate(200),
                        reason: .autoCleanup
                    )),
                version: BrowserSyncVersion(logicalClock: 20, deviceID: fixedUUID(15))
            ),
        ]
        var journal = BrowserSyncJournal(deviceID: fixedUUID(16))
        try journal.merge(records)

        let materialized = try journal.materializedSession(applyingTo: local)

        XCTAssertEqual(materialized.selectedSpace?.tabs.map(\.id), [tab.id])
        XCTAssertTrue(try XCTUnwrap(materialized.selectedSpace).archivedTabs.isEmpty)
    }

    func testNewerActivationDefeatsANewerClockRetentionTombstone() throws {
        let local = oneSpaceSession(lastActivatedAt: fixedDate(300))
        let space = try XCTUnwrap(local.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let tabID = BrowserSyncRecordID(kind: .tab, value: tab.id.rawValue)
        let active = BrowserSyncRecord.save(
            .tab(syncTab(tab, spaceID: space.id)),
            version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(140))
        )
        let staleCleanup = BrowserSyncRecord.delete(
            id: tabID,
            spaceID: space.id,
            version: BrowserSyncVersion(logicalClock: 100, deviceID: fixedUUID(141)),
            reason: .retention,
            at: fixedDate(200)
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(142))

        try journal.merge([staleCleanup])
        try journal.merge([active])

        let resolved = try XCTUnwrap(journal.records.first { $0.id == tabID })
        guard case .tab(let resolvedTab)? = resolved.payload else {
            return XCTFail("Expected recent activity to retain the tab")
        }
        XCTAssertEqual(resolvedTab.lastActivatedAt, fixedDate(300))
    }

    func testNewerArchiveWinsWhenTabActivityIsStale() throws {
        let local = oneSpaceSession(lastActivatedAt: fixedDate(100))
        let space = try XCTUnwrap(local.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let records = [
            spaceRecord(space, clock: 1),
            BrowserSyncRecord.save(
                .tab(syncTab(tab, spaceID: space.id)),
                version: BrowserSyncVersion(logicalClock: 10, deviceID: fixedUUID(17))
            ),
            BrowserSyncRecord.save(
                .archive(
                    BrowserSyncArchive(
                        tab: syncTab(tab, spaceID: space.id),
                        archivedAt: fixedDate(200),
                        reason: .autoCleanup
                    )),
                version: BrowserSyncVersion(logicalClock: 20, deviceID: fixedUUID(18))
            ),
        ]
        var journal = BrowserSyncJournal(deviceID: fixedUUID(19))
        try journal.merge(records)

        let materialized = try journal.materializedSession(applyingTo: local)

        XCTAssertFalse(try XCTUnwrap(materialized.selectedSpace).tabs.contains { $0.id == tab.id })
        XCTAssertTrue(try XCTUnwrap(materialized.selectedSpace).archivedTabs.contains { $0.id == tab.id })
    }

    func testMaterializationPreservesDeviceSelectionDefaultAndCredentialPreferences() throws {
        let source = BrowserSession.preview
        var local = source
        let work = try XCTUnwrap(local.spaces.first)
        let personal = try XCTUnwrap(local.spaces.last)
        local.setDefaultSpace(work.id)
        local.selectSpace(personal.id)
        let selected = try XCTUnwrap(personal.pinnedTabs.last?.id)
        local.selectTab(selected, at: fixedDate(500))
        local.spaces[1].credentialPreferences = BrowserCredentialPreferences(
            syncsCrestPasswordsWithICloud: false,
            alsoOffersSaveToSystemPasswords: true
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(20))
        try journal.stage(session: source, at: fixedDate(100))

        let result = try journal.materializedSession(applyingTo: local)

        XCTAssertEqual(result.selectedSpaceID, personal.id)
        XCTAssertEqual(result.defaultSpaceID, work.id)
        XCTAssertEqual(result.selectedTab?.id, selected)
        XCTAssertEqual(
            result.selectedSpace?.credentialPreferences,
            local.selectedSpace?.credentialPreferences
        )
    }

    func testDisabledCurrentAndHistorySyncPreserveLocalDeviceData() throws {
        var remote = oneSpaceSession()
        remote.spaces[0].name = "Renamed remotely"
        remote.spaces[0].history = [history(id: fixedUUID(21), path: "remote")]
        var local = remote
        local.spaces[0].tabs = [
            BrowserTab(
                id: TabID(rawValue: fixedUUID(22)),
                title: "Local current tab",
                url: try XCTUnwrap(URL(string: "https://example.com/local")),
                placement: .current,
                lastActivatedAt: fixedDate(300)
            )
        ]
        local.spaces[0].selectedTabID = local.spaces[0].tabs[0].id
        local.spaces[0].history = [history(id: fixedUUID(23), path: "local")]
        let preferences = BrowserSyncPreferences(
            savedStructure: true,
            currentTabs: false,
            historyAndArchive: false,
            extensionSettings: false
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(24), preferences: preferences)
        try journal.stage(session: remote, at: fixedDate(100))

        let result = try journal.materializedSession(applyingTo: local)

        XCTAssertEqual(result.selectedSpace?.name, "Renamed remotely")
        XCTAssertEqual(result.selectedTab?.title, "Local current tab")
        XCTAssertEqual(result.selectedSpace?.history.map(\.url), local.selectedSpace?.history.map(\.url))
    }

    func testTwoDevicesConvergeAfterConcurrentRenames() throws {
        let base = oneSpaceSession()
        var first = BrowserSyncJournal(deviceID: fixedUUID(30))
        var second = BrowserSyncJournal(deviceID: fixedUUID(31))
        try first.stage(session: base, at: fixedDate(100))
        try second.merge(first.records)
        first.markUploaded(first.pendingRecordIDs)

        var firstEdit = base
        firstEdit.spaces[0].name = "Athena"
        try first.stage(session: firstEdit, at: fixedDate(200))
        var secondEdit = base
        secondEdit.spaces[0].name = "Orion"
        try second.stage(session: secondEdit, at: fixedDate(200))

        let firstChanges = first.records
        let secondChanges = second.records
        try first.merge(secondChanges)
        try second.merge(firstChanges)

        let firstResult = try first.materializedSession(applyingTo: base)
        let secondResult = try second.materializedSession(applyingTo: base)
        XCTAssertEqual(firstResult.selectedSpace?.name, secondResult.selectedSpace?.name)
        XCTAssertEqual(first.records, second.records)
    }

    func testCrossSpaceRecordCollisionFailsClosed() throws {
        let firstSpace = SpaceID(rawValue: fixedUUID(40))
        let secondSpace = SpaceID(rawValue: fixedUUID(41))
        let tabID = TabID(rawValue: fixedUUID(42))
        let first = BrowserSyncTab(
            id: tabID,
            spaceID: firstSpace,
            title: "First",
            url: nil,
            symbol: "globe",
            placement: .current,
            folderID: nil,
            orderToken: "a",
            lastActivatedAt: fixedDate(1)
        )
        var second = first
        second = BrowserSyncTab(
            id: tabID,
            spaceID: secondSpace,
            title: "Second",
            url: nil,
            symbol: "globe",
            placement: .current,
            folderID: nil,
            orderToken: "a",
            lastActivatedAt: fixedDate(2)
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(43))
        try journal.merge([
            BrowserSyncRecord.save(
                .tab(first),
                version: BrowserSyncVersion(logicalClock: 1, deviceID: fixedUUID(44))
            )
        ])

        XCTAssertThrowsError(
            try journal.merge([
                BrowserSyncRecord.save(
                    .tab(second),
                    version: BrowserSyncVersion(logicalClock: 2, deviceID: fixedUUID(45))
                )
            ])
        ) { error in
            XCTAssertEqual(
                error as? BrowserSyncError,
                .crossSpaceConflict(BrowserSyncRecordID(kind: .tab, value: tabID.rawValue).recordName)
            )
        }
    }

    func testMalformedRecordIdentityFailsClosed() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let payload = BrowserSyncPayload.tab(syncTab(tab, spaceID: space.id))
        let record = BrowserSyncRecord(
            id: BrowserSyncRecordID(kind: .tab, value: fixedUUID(50)),
            spaceID: space.id,
            version: BrowserSyncVersion(logicalClock: 1, deviceID: fixedUUID(51)),
            payload: payload,
            tombstone: nil
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(52))

        XCTAssertThrowsError(try journal.merge([record])) { error in
            XCTAssertEqual(
                error as? BrowserSyncError,
                .recordIdentityMismatch(record.id.recordName)
            )
        }
    }

    func testMaterializationRejectsDuplicateProfilesAndDanglingFolders() throws {
        let first = oneSpaceSession(spaceID: SpaceID(rawValue: fixedUUID(60)), profileID: fixedUUID(62))
        let second = oneSpaceSession(
            spaceID: SpaceID(rawValue: fixedUUID(61)),
            profileID: fixedUUID(62),
            tabID: TabID(rawValue: fixedUUID(68))
        )
        var duplicateProfiles = BrowserSyncJournal(deviceID: fixedUUID(63))
        try duplicateProfiles.stage(
            session: BrowserSession(
                spaces: [try XCTUnwrap(first.selectedSpace), try XCTUnwrap(second.selectedSpace)],
                selectedSpaceID: first.selectedSpaceID
            ),
            at: fixedDate(1)
        )

        XCTAssertThrowsError(try duplicateProfiles.materializedSession(applyingTo: first)) { error in
            XCTAssertEqual(error as? BrowserSyncError, .duplicateProfile(fixedUUID(62)))
        }

        let base = oneSpaceSession()
        let space = try XCTUnwrap(base.selectedSpace)
        let tabID = TabID(rawValue: fixedUUID(64))
        let danglingFolderID = FolderID(rawValue: fixedUUID(65))
        let dangling = BrowserSyncTab(
            id: tabID,
            spaceID: space.id,
            title: "Dangling",
            url: nil,
            symbol: "globe",
            placement: .saved,
            folderID: danglingFolderID,
            orderToken: "a",
            lastActivatedAt: fixedDate(1)
        )
        // A folder with no record at all is now read as one that has not arrived
        // yet, because a fetch has no ordering guarantee and failing here loses
        // the whole batch. Giving the folder a record in another Space keeps this
        // case what it was written to be: a reference no delivery order explains.
        let strayFolder = BrowserSyncFolder(
            id: danglingFolderID,
            spaceID: SpaceID(rawValue: fixedUUID(71)),
            title: "Another Space",
            symbol: "folder",
            orderToken: "a"
        )
        var hostile = BrowserSyncJournal(deviceID: fixedUUID(66))
        try hostile.merge([
            spaceRecord(space, clock: 1),
            BrowserSyncRecord.save(
                .tab(dangling),
                version: BrowserSyncVersion(logicalClock: 2, deviceID: fixedUUID(67))
            ),
            BrowserSyncRecord.save(
                .folder(strayFolder),
                version: BrowserSyncVersion(logicalClock: 3, deviceID: fixedUUID(67))
            ),
        ])
        XCTAssertThrowsError(try hostile.materializedSession(applyingTo: base)) { error in
            XCTAssertEqual(error as? BrowserSyncError, .danglingFolder(tabID))
        }
    }

    func testMaterializationRejectsChangingAnExistingSpacesProfileIdentity()
        throws
    {
        let local = oneSpaceSession()
        let space = try XCTUnwrap(local.selectedSpace)
        let changedProfileID = fixedUUID(69)
        let remoteSpace = BrowserSyncSpace(
            id: space.id,
            profileID: changedProfileID,
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            orderToken: "a"
        )
        let record = BrowserSyncRecord.save(
            .space(remoteSpace),
            version: BrowserSyncVersion(
                logicalClock: 1,
                deviceID: fixedUUID(70)
            )
        )

        XCTAssertThrowsError(
            try BrowserSyncMaterializer.materialize(
                records: [record],
                preferences: .default,
                localSession: local
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserSyncError,
                .immutableProfileChanged(space.id)
            )
        }
    }

    func testJournalPersistsAndRejectsCorruptData() throws {
        let suiteName = "BrowserSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserSyncJournalPersistence(
            defaults: defaults,
            key: "journal"
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(70))
        try journal.stage(session: oneSpaceSession(), at: fixedDate(1))

        try persistence.save(journal)
        XCTAssertEqual(try persistence.load(), journal)

        defaults.set(Data("not-json".utf8), forKey: "journal")
        XCTAssertThrowsError(try persistence.load()) { error in
            XCTAssertEqual(error as? BrowserSyncJournalPersistenceError, .decodingFailed)
        }
    }

    func testDefaultJournalPersistenceUsesDedicatedDefaultsSuite() throws {
        let key = "BrowserSyncTests.\(UUID().uuidString)"
        let isolatedDefaults = try XCTUnwrap(
            UserDefaults(suiteName: "com.pauldavis.crest.sync-journal")
        )
        let standardDefaults = UserDefaults.standard
        defer {
            isolatedDefaults.removeObject(forKey: key)
            standardDefaults.removeObject(forKey: key)
        }
        var journal = BrowserSyncJournal(deviceID: fixedUUID(701))
        try journal.stage(session: oneSpaceSession(), at: fixedDate(1))

        try UserDefaultsBrowserSyncJournalPersistence(key: key).save(journal)

        XCTAssertNotNil(isolatedDefaults.data(forKey: key))
        XCTAssertNil(standardDefaults.data(forKey: key))
    }

    func testDefaultJournalPersistenceMigratesLegacyStandardJournal() throws {
        let key = "BrowserSyncTests.\(UUID().uuidString)"
        let isolatedDefaults = try XCTUnwrap(
            UserDefaults(suiteName: "com.pauldavis.crest.sync-journal")
        )
        let standardDefaults = UserDefaults.standard
        defer {
            isolatedDefaults.removeObject(forKey: key)
            standardDefaults.removeObject(forKey: key)
        }
        var journal = BrowserSyncJournal(deviceID: fixedUUID(702))
        try journal.stage(session: oneSpaceSession(), at: fixedDate(1))
        standardDefaults.set(try JSONEncoder().encode(journal), forKey: key)

        let loaded = try UserDefaultsBrowserSyncJournalPersistence(key: key).load()

        XCTAssertEqual(loaded, journal)
        XCTAssertNotNil(isolatedDefaults.data(forKey: key))
    }

    func testCoordinatorRecoversACorruptLocalJournalAndPersistsFreshState() throws {
        let persistence = CorruptBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: persistence,
            deviceID: fixedUUID(71)
        )

        XCTAssertEqual(coordinator.status, .recoveredCorruptLocalJournal)
        try coordinator.stage(session: oneSpaceSession(), at: fixedDate(1))

        XCTAssertNotNil(persistence.savedJournal)
        XCTAssertFalse(coordinator.journal.records.isEmpty)
    }

    func testCoordinatorDoesNotPublishAJournalMutationWhenPersistenceFails() {
        let coordinator = BrowserSyncCoordinator(
            persistence: FailingSaveBrowserSyncJournalPersistence(),
            deviceID: fixedUUID(72)
        )
        let original = coordinator.journal

        XCTAssertThrowsError(
            try coordinator.stage(
                session: oneSpaceSession(),
                at: fixedDate(1)
            )
        )

        XCTAssertEqual(coordinator.journal, original)
    }

    func testUseThisDeviceRebasesLocalRecordsAboveCloudAndDeletesCloudOnlyContent() throws {
        let localSession = oneSpaceSession()
        var cloudSession = localSession
        cloudSession.spaces[0].name = "Cloud copy"
        let cloudOnlyTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(910)),
            title: "Cloud only",
            url: URL(string: "https://cloud.example.com"),
            symbol: "icloud",
            placement: .current,
            lastActivatedAt: fixedDate(900)
        )
        cloudSession.spaces[0].tabs.append(cloudOnlyTab)

        var cloud = BrowserSyncJournal(deviceID: fixedUUID(911))
        try cloud.stage(session: cloudSession, at: fixedDate(900))
        let remoteMaximumClock = try XCTUnwrap(cloud.records.map(\.version.logicalClock).max())
        let persistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: persistence,
            deviceID: fixedUUID(912)
        )

        try coordinator.prepareToOverwriteCloud(
            with: localSession,
            remoteRecords: cloud.records,
            at: fixedDate(1_000)
        )

        let journal = coordinator.journal
        let spaceRecord = try XCTUnwrap(
            journal.records.first { $0.id.kind == .space }
        )
        guard case .space(let space)? = spaceRecord.payload else {
            return XCTFail("Expected the local Space payload")
        }
        XCTAssertEqual(space.name, localSession.spaces[0].name)
        XCTAssertGreaterThan(spaceRecord.version.logicalClock, remoteMaximumClock)

        let cloudOnlyRecord = try XCTUnwrap(
            journal.records.first {
                $0.id
                    == BrowserSyncRecordID(
                        kind: .tab,
                        value: cloudOnlyTab.id.rawValue
                    )
            }
        )
        XCTAssertNil(cloudOnlyRecord.payload)
        XCTAssertNotNil(cloudOnlyRecord.tombstone)
        XCTAssertGreaterThan(cloudOnlyRecord.version.logicalClock, remoteMaximumClock)
        XCTAssertEqual(journal.pendingRecordIDs, Set(journal.records.map(\.id)))
        XCTAssertEqual(persistence.journal, journal)
    }

    func testUseICloudReplacesTheLocalProjectionWithoutUploadingItBack() throws {
        let localSession = oneSpaceSession()
        var cloudSession = localSession
        cloudSession.spaces[0].name = "Chosen from iCloud"
        var cloud = BrowserSyncJournal(deviceID: fixedUUID(920))
        try cloud.stage(session: cloudSession, at: fixedDate(900))
        cloud.markUploaded(cloud.pendingRecordIDs)

        let persistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: persistence,
            deviceID: fixedUUID(921)
        )
        try coordinator.stage(session: localSession, at: fixedDate(100))

        let resolved = try coordinator.replaceLocalWithCloud(
            cloud.records,
            replacing: localSession
        )

        XCTAssertEqual(resolved.spaces[0].name, "Chosen from iCloud")
        XCTAssertTrue(coordinator.journal.pendingRecordIDs.isEmpty)
        XCTAssertEqual(coordinator.journal.records, cloud.records)
        XCTAssertEqual(persistence.journal, coordinator.journal)
    }

    func testUseICloudWithAnEmptyCloudClearsLocalSyncedContent() throws {
        let localSession = oneSpaceSession()
        let localSpaceID = localSession.spaces[0].id
        let persistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: persistence,
            deviceID: fixedUUID(922)
        )
        try coordinator.stage(session: localSession, at: fixedDate(100))

        let resolved = try coordinator.replaceLocalWithCloud(
            [],
            replacing: localSession
        )

        XCTAssertEqual(resolved.spaces.count, 1)
        XCTAssertNotEqual(resolved.spaces[0].id, localSpaceID)
        XCTAssertEqual(resolved.spaces[0].name, "Space 1")
        XCTAssertEqual(resolved.spaces[0].tabs.count, 1)
        XCTAssertTrue(resolved.spaces[0].tabs[0].isStartPage)
        XCTAssertTrue(coordinator.journal.records.isEmpty)
        XCTAssertTrue(coordinator.journal.pendingRecordIDs.isEmpty)
    }

    /// CKSyncEngine splits a first sync across events and guarantees no ordering
    /// between them, so a Space's tabs and history can arrive in one batch and the
    /// `CrestSpace` record that owns them in a later one. The earlier batch must
    /// not read the missing parent as a deletion: it restages above the remote
    /// clock, so the tombstones would outrank the real records and delete the
    /// other device's content on every device.
    func testChildRecordsArrivingBeforeTheirSpaceAreNotTombstoned() throws {
        let cloudSpaceID = SpaceID(rawValue: fixedUUID(940))
        var cloudSession = oneSpaceSession(
            spaceID: cloudSpaceID,
            profileID: fixedUUID(941),
            tabID: TabID(rawValue: fixedUUID(942))
        )
        cloudSession.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/cloud")),
            title: "Cloud history",
            at: fixedDate(800)
        )
        var cloud = BrowserSyncJournal(deviceID: fixedUUID(943))
        try cloud.stage(session: cloudSession, at: fixedDate(900))
        let cloudSpaceRecordID = BrowserSyncRecordID(
            kind: .space,
            value: cloudSpaceID.rawValue
        )
        let cloudSpaceRecord = try XCTUnwrap(
            cloud.records.first { $0.id == cloudSpaceRecordID }
        )
        let childRecords = cloud.records.filter { $0.id != cloudSpaceRecordID }
        XCTAssertFalse(childRecords.isEmpty)

        let localSession = oneSpaceSession()
        let persistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: persistence,
            deviceID: fixedUUID(944)
        )
        try coordinator.stage(session: localSession, at: fixedDate(100))

        let afterChildren = try coordinator.merge(
            remoteRecords: childRecords,
            into: localSession
        )

        XCTAssertNil(afterChildren.space(id: cloudSpaceID))
        for child in childRecords {
            let stored = try XCTUnwrap(
                coordinator.journal.records.first { $0.id == child.id }
            )
            XCTAssertEqual(
                stored,
                child,
                "\(child.id.recordName) did not survive its Space's absence"
            )
        }

        let afterSpace = try coordinator.merge(
            remoteRecords: [cloudSpaceRecord],
            into: afterChildren
        )

        let restored = try XCTUnwrap(afterSpace.space(id: cloudSpaceID))
        XCTAssertEqual(
            restored.tabs.map(\.id),
            cloudSession.spaces[0].tabs.map(\.id)
        )
        XCTAssertEqual(
            restored.history.map(\.id),
            cloudSession.spaces[0].history.map(\.id)
        )
        XCTAssertTrue(coordinator.journal.records.allSatisfy { $0.payload != nil })
    }

    func testDeletingASpaceStillTombstonesTheRecordsItOwned() throws {
        let deletedSpaceID = SpaceID(rawValue: fixedUUID(950))
        let deletedTabID = TabID(rawValue: fixedUUID(951))
        let deleted = oneSpaceSession(
            spaceID: deletedSpaceID,
            profileID: fixedUUID(952),
            tabID: deletedTabID
        )
        let retained = oneSpaceSession(
            spaceID: SpaceID(rawValue: fixedUUID(953)),
            profileID: fixedUUID(954),
            tabID: TabID(rawValue: fixedUUID(955))
        )
        var session = BrowserSession(
            spaces: [deleted.spaces[0], retained.spaces[0]],
            selectedSpaceID: deletedSpaceID
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(956))
        try journal.stage(session: session, at: fixedDate(100))
        journal.markUploaded(journal.pendingRecordIDs)

        session.spaces.removeAll { $0.id == deletedSpaceID }
        session.selectedSpaceID = retained.spaces[0].id
        try journal.stage(session: session, at: fixedDate(200))

        let deletedSpaceRecordID = BrowserSyncRecordID(
            kind: .space,
            value: deletedSpaceID.rawValue
        )
        let deletedTabRecordID = BrowserSyncRecordID(
            kind: .tab,
            value: deletedTabID.rawValue
        )
        let spaceRecord = try XCTUnwrap(
            journal.records.first { $0.id == deletedSpaceRecordID }
        )
        XCTAssertNil(spaceRecord.payload)
        let tabRecord = try XCTUnwrap(
            journal.records.first { $0.id == deletedTabRecordID }
        )
        XCTAssertNil(tabRecord.payload)
        XCTAssertEqual(tabRecord.tombstone?.reason, .explicitDelete)
    }

    /// A journal recovered from corruption holds no Space records at all, so the
    /// first stage after the recovery recreates them. Judging an orphan's parent
    /// against the journal being written would find the Space it just added and
    /// delete the record that is still waiting for it.
    func testOrphansSurviveTheStageThatFirstRecreatesTheirSpaceRecord() throws {
        let session = oneSpaceSession()
        let orphanTab = BrowserSyncTab(
            id: TabID(rawValue: fixedUUID(960)),
            spaceID: session.spaces[0].id,
            title: "From iCloud",
            url: URL(string: "https://example.com/orphan"),
            symbol: "globe",
            placement: .current,
            orderToken: "b",
            lastActivatedAt: fixedDate(300)
        )
        let orphan = BrowserSyncRecord.save(
            .tab(orphanTab),
            version: BrowserSyncVersion(logicalClock: 9, deviceID: fixedUUID(961))
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(962))
        try journal.merge([orphan])

        try journal.stage(session: session, at: fixedDate(400))

        XCTAssertEqual(journal.records.first { $0.id == orphan.id }, orphan)
    }

    /// The same delivery-order problem one level down. A saved tab used to fail the
    /// entire merge when its folder record had not arrived yet, and because the
    /// change token advances either way, every record in that batch was lost for
    /// good.
    func testSavedTabArrivingBeforeItsFolderSurvivesTheNextBatch() throws {
        let cloudSpaceID = SpaceID(rawValue: fixedUUID(980))
        let folder = SavedFolder(
            id: FolderID(rawValue: fixedUUID(981)),
            title: "Reading",
            symbol: "folder"
        )
        let currentTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(982)),
            title: "Current",
            url: URL(string: "https://example.com/current"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: fixedDate(500)
        )
        let savedTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(983)),
            title: "Saved",
            url: URL(string: "https://example.com/saved"),
            symbol: "bookmark",
            placement: .saved,
            folderID: folder.id,
            lastActivatedAt: fixedDate(501)
        )
        let cloudSpace = BrowserSpace(
            id: cloudSpaceID,
            profile: BrowsingProfile(id: fixedUUID(984)),
            name: "Cloud",
            symbol: "cloud",
            accent: .indigo,
            folders: [folder],
            tabs: [currentTab, savedTab],
            selectedTabID: currentTab.id
        )
        var cloud = BrowserSyncJournal(deviceID: fixedUUID(985))
        try cloud.stage(
            session: BrowserSession(
                spaces: [cloudSpace],
                selectedSpaceID: cloudSpaceID
            ),
            at: fixedDate(900)
        )
        let folderRecordID = BrowserSyncRecordID(
            kind: .folder,
            value: folder.id.rawValue
        )
        let savedTabRecordID = BrowserSyncRecordID(
            kind: .tab,
            value: savedTab.id.rawValue
        )
        let folderRecord = try XCTUnwrap(
            cloud.records.first { $0.id == folderRecordID }
        )
        let firstBatch = cloud.records.filter { $0.id != folderRecordID }

        let localSession = oneSpaceSession()
        let persistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: persistence,
            deviceID: fixedUUID(986)
        )
        try coordinator.stage(session: localSession, at: fixedDate(100))

        let afterTabs = try coordinator.merge(
            remoteRecords: firstBatch,
            into: localSession
        )

        let heldBack = try XCTUnwrap(afterTabs.space(id: cloudSpaceID))
        XCTAssertEqual(heldBack.tabs.map(\.id), [currentTab.id])
        XCTAssertTrue(heldBack.folders.isEmpty)
        XCTAssertEqual(
            coordinator.journal.records.first { $0.id == savedTabRecordID },
            firstBatch.first { $0.id == savedTabRecordID },
            "The saved tab did not survive its folder's absence"
        )

        let afterFolder = try coordinator.merge(
            remoteRecords: [folderRecord],
            into: afterTabs
        )

        let restored = try XCTUnwrap(afterFolder.space(id: cloudSpaceID))
        XCTAssertEqual(restored.folders.map(\.id), [folder.id])
        let restoredSavedTab = try XCTUnwrap(
            restored.tabs.first { $0.id == savedTab.id }
        )
        XCTAssertEqual(restoredSavedTab.placement, .saved)
        XCTAssertEqual(restoredSavedTab.folderID, folder.id)
        XCTAssertTrue(coordinator.journal.records.allSatisfy { $0.payload != nil })
    }

    /// The other side of the same discriminator: a folder somebody deleted keeps a
    /// tombstone, so the tabs it held are still deleted everywhere.
    func testDeletingAFolderStillTombstonesTheTabsItHeld() throws {
        let spaceID = SpaceID(rawValue: fixedUUID(990))
        let folder = SavedFolder(
            id: FolderID(rawValue: fixedUUID(991)),
            title: "Reading",
            symbol: "folder"
        )
        let currentTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(992)),
            title: "Current",
            url: URL(string: "https://example.com/current"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: fixedDate(500)
        )
        let savedTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(993)),
            title: "Saved",
            url: URL(string: "https://example.com/saved"),
            symbol: "bookmark",
            placement: .saved,
            folderID: folder.id,
            lastActivatedAt: fixedDate(501)
        )
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: fixedUUID(994)),
            name: "Shared",
            symbol: "cloud",
            accent: .indigo,
            folders: [folder],
            tabs: [currentTab, savedTab],
            selectedTabID: currentTab.id
        )
        let session = BrowserSession(spaces: [space], selectedSpaceID: spaceID)
        let persistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: persistence,
            deviceID: fixedUUID(995)
        )
        try coordinator.stage(session: session, at: fixedDate(100))
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let savedTabRecordID = BrowserSyncRecordID(
            kind: .tab,
            value: savedTab.id.rawValue
        )
        let folderDeletion = BrowserSyncRecord.delete(
            id: BrowserSyncRecordID(kind: .folder, value: folder.id.rawValue),
            spaceID: spaceID,
            version: BrowserSyncVersion(
                logicalClock: 900,
                deviceID: fixedUUID(996)
            ),
            reason: .explicitDelete,
            at: fixedDate(900)
        )

        let resolved = try coordinator.merge(
            remoteRecords: [folderDeletion],
            into: session
        )

        XCTAssertTrue(try XCTUnwrap(resolved.space(id: spaceID)).folders.isEmpty)
        XCTAssertEqual(
            resolved.space(id: spaceID)?.tabs.map(\.id),
            [currentTab.id]
        )
        let tabRecord = try XCTUnwrap(
            coordinator.journal.records.first { $0.id == savedTabRecordID }
        )
        XCTAssertNil(tabRecord.payload)
        XCTAssertEqual(tabRecord.tombstone?.reason, .superseded)
    }

    /// The last layer of the same problem. A nested folder used to fail the whole
    /// fetch when the folder above it had not arrived, and the protection has to
    /// reach the entire chain: the tab's own folder is present here, and so is
    /// that folder's parent — the record still missing is two levels up.
    func testNestedFoldersArrivingBeforeTheirRootSurviveTheNextBatch() throws {
        let cloudSpaceID = SpaceID(rawValue: fixedUUID(1_010))
        let root = SavedFolder(
            id: FolderID(rawValue: fixedUUID(1_011)),
            title: "Root",
            symbol: "folder"
        )
        let middle = SavedFolder(
            id: FolderID(rawValue: fixedUUID(1_012)),
            title: "Middle",
            symbol: "folder",
            parentID: root.id
        )
        let leaf = SavedFolder(
            id: FolderID(rawValue: fixedUUID(1_013)),
            title: "Leaf",
            symbol: "folder",
            parentID: middle.id
        )
        let currentTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(1_014)),
            title: "Current",
            url: URL(string: "https://example.com/current"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: fixedDate(500)
        )
        let savedTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(1_015)),
            title: "Deep",
            url: URL(string: "https://example.com/deep"),
            symbol: "bookmark",
            placement: .saved,
            folderID: leaf.id,
            lastActivatedAt: fixedDate(501)
        )
        let cloudSpace = BrowserSpace(
            id: cloudSpaceID,
            profile: BrowsingProfile(id: fixedUUID(1_016)),
            name: "Cloud",
            symbol: "cloud",
            accent: .indigo,
            folders: [root, middle, leaf],
            tabs: [currentTab, savedTab],
            selectedTabID: currentTab.id
        )
        var cloud = BrowserSyncJournal(deviceID: fixedUUID(1_017))
        try cloud.stage(
            session: BrowserSession(
                spaces: [cloudSpace],
                selectedSpaceID: cloudSpaceID
            ),
            at: fixedDate(900)
        )
        let rootRecordID = BrowserSyncRecordID(
            kind: .folder,
            value: root.id.rawValue
        )
        let rootRecord = try XCTUnwrap(cloud.records.first { $0.id == rootRecordID })
        let firstBatch = cloud.records.filter { $0.id != rootRecordID }
        let heldBackIDs = [
            BrowserSyncRecordID(kind: .folder, value: middle.id.rawValue),
            BrowserSyncRecordID(kind: .folder, value: leaf.id.rawValue),
            BrowserSyncRecordID(kind: .tab, value: savedTab.id.rawValue),
        ]

        let localSession = oneSpaceSession()
        let persistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: persistence,
            deviceID: fixedUUID(1_018)
        )
        try coordinator.stage(session: localSession, at: fixedDate(100))

        let afterSubtree = try coordinator.merge(
            remoteRecords: firstBatch,
            into: localSession
        )

        let waiting = try XCTUnwrap(afterSubtree.space(id: cloudSpaceID))
        XCTAssertTrue(waiting.folders.isEmpty)
        XCTAssertEqual(waiting.tabs.map(\.id), [currentTab.id])
        for recordID in heldBackIDs {
            XCTAssertEqual(
                coordinator.journal.records.first { $0.id == recordID },
                firstBatch.first { $0.id == recordID },
                "\(recordID.recordName) did not survive its missing ancestor"
            )
        }

        let afterRoot = try coordinator.merge(
            remoteRecords: [rootRecord],
            into: afterSubtree
        )

        let restored = try XCTUnwrap(afterRoot.space(id: cloudSpaceID))
        XCTAssertEqual(restored.folders.map(\.id), [root.id, middle.id, leaf.id])
        XCTAssertEqual(restored.folders.map(\.parentID), [nil, root.id, middle.id])
        let restoredSavedTab = try XCTUnwrap(
            restored.tabs.first { $0.id == savedTab.id }
        )
        XCTAssertEqual(restoredSavedTab.folderID, leaf.id)
        XCTAssertTrue(coordinator.journal.records.allSatisfy { $0.payload != nil })
    }

    /// Deleting a folder in the middle of a chain still reaches everything under
    /// it: the folder below and the tab inside that folder both go.
    func testDeletingAParentFolderStillTombstonesItsWholeSubtree() throws {
        let spaceID = SpaceID(rawValue: fixedUUID(1_020))
        let root = SavedFolder(
            id: FolderID(rawValue: fixedUUID(1_021)),
            title: "Root",
            symbol: "folder"
        )
        let middle = SavedFolder(
            id: FolderID(rawValue: fixedUUID(1_022)),
            title: "Middle",
            symbol: "folder",
            parentID: root.id
        )
        let leaf = SavedFolder(
            id: FolderID(rawValue: fixedUUID(1_023)),
            title: "Leaf",
            symbol: "folder",
            parentID: middle.id
        )
        let currentTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(1_024)),
            title: "Current",
            url: URL(string: "https://example.com/current"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: fixedDate(500)
        )
        let savedTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(1_025)),
            title: "Deep",
            url: URL(string: "https://example.com/deep"),
            symbol: "bookmark",
            placement: .saved,
            folderID: leaf.id,
            lastActivatedAt: fixedDate(501)
        )
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: fixedUUID(1_026)),
            name: "Shared",
            symbol: "cloud",
            accent: .indigo,
            folders: [root, middle, leaf],
            tabs: [currentTab, savedTab],
            selectedTabID: currentTab.id
        )
        let session = BrowserSession(spaces: [space], selectedSpaceID: spaceID)
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: fixedUUID(1_027)
        )
        try coordinator.stage(session: session, at: fixedDate(100))
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let middleDeletion = BrowserSyncRecord.delete(
            id: BrowserSyncRecordID(kind: .folder, value: middle.id.rawValue),
            spaceID: spaceID,
            version: BrowserSyncVersion(
                logicalClock: 900,
                deviceID: fixedUUID(1_028)
            ),
            reason: .explicitDelete,
            at: fixedDate(900)
        )

        let resolved = try coordinator.merge(
            remoteRecords: [middleDeletion],
            into: session
        )

        XCTAssertEqual(
            try XCTUnwrap(resolved.space(id: spaceID)).folders.map(\.id),
            [root.id]
        )
        XCTAssertEqual(
            resolved.space(id: spaceID)?.tabs.map(\.id),
            [currentTab.id]
        )
        for recordID in [
            BrowserSyncRecordID(kind: .folder, value: leaf.id.rawValue),
            BrowserSyncRecordID(kind: .tab, value: savedTab.id.rawValue),
        ] {
            let record = try XCTUnwrap(
                coordinator.journal.records.first { $0.id == recordID }
            )
            XCTAssertNil(
                record.payload,
                "\(recordID.recordName) outlived the folder that held it"
            )
        }
        let rootRecord = try XCTUnwrap(
            coordinator.journal.records.first {
                $0.id == BrowserSyncRecordID(kind: .folder, value: root.id.rawValue)
            }
        )
        XCTAssertNotNil(rootRecord.payload)
    }

    /// A parent folder recorded in a different Space is not delivery order either.
    func testAFolderWhoseParentBelongsToAnotherSpaceStillFailsClosed() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let strayParentID = FolderID(rawValue: fixedUUID(1_030))
        let child = BrowserSyncFolder(
            id: FolderID(rawValue: fixedUUID(1_031)),
            spaceID: space.id,
            title: "Child",
            symbol: "folder",
            parentID: strayParentID,
            orderToken: "a"
        )
        let strayParent = BrowserSyncFolder(
            id: strayParentID,
            spaceID: SpaceID(rawValue: fixedUUID(1_032)),
            title: "Another Space",
            symbol: "folder",
            orderToken: "a"
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(1_033))
        try journal.merge([
            spaceRecord(space, clock: 1),
            BrowserSyncRecord.save(
                .folder(child),
                version: BrowserSyncVersion(
                    logicalClock: 2,
                    deviceID: fixedUUID(1_034)
                )
            ),
            BrowserSyncRecord.save(
                .folder(strayParent),
                version: BrowserSyncVersion(
                    logicalClock: 3,
                    deviceID: fixedUUID(1_034)
                )
            ),
        ])

        XCTAssertThrowsError(
            try journal.materializedSession(applyingTo: session)
        ) { error in
            XCTAssertEqual(
                error as? BrowserSyncError,
                .invalidFolderHierarchy(space.id)
            )
        }
    }

    /// A folder record that names a different Space cannot be explained by
    /// delivery order, so the merge still refuses it outright.
    func testASavedTabReferencingAnotherSpacesFolderStillFailsClosed() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.selectedSpace)
        let tabID = TabID(rawValue: fixedUUID(997))
        let folderID = FolderID(rawValue: fixedUUID(998))
        let strayFolder = BrowserSyncFolder(
            id: folderID,
            spaceID: SpaceID(rawValue: fixedUUID(999)),
            title: "Another Space",
            symbol: "folder",
            orderToken: "a"
        )
        let dangling = BrowserSyncTab(
            id: tabID,
            spaceID: space.id,
            title: "Dangling",
            url: nil,
            symbol: "globe",
            placement: .saved,
            folderID: folderID,
            orderToken: "a",
            lastActivatedAt: fixedDate(1)
        )
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: fixedUUID(1_000)
        )
        let remote = [
            spaceRecord(space, clock: 1),
            BrowserSyncRecord.save(
                .tab(dangling),
                version: BrowserSyncVersion(
                    logicalClock: 2,
                    deviceID: fixedUUID(1_001)
                )
            ),
            BrowserSyncRecord.save(
                .folder(strayFolder),
                version: BrowserSyncVersion(
                    logicalClock: 3,
                    deviceID: fixedUUID(1_001)
                )
            ),
        ]

        XCTAssertThrowsError(
            try coordinator.merge(remoteRecords: remote, into: session)
        ) { error in
            XCTAssertEqual(error as? BrowserSyncError, .danglingFolder(tabID))
        }
    }

    func testReplacingICloudWithThisDeviceLeavesUnsyncedCategoriesAlone() throws {
        var cloudSession = oneSpaceSession()
        cloudSession.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/cloud")),
            title: "Cloud history",
            at: fixedDate(800)
        )
        var cloud = BrowserSyncJournal(deviceID: fixedUUID(970))
        try cloud.stage(session: cloudSession, at: fixedDate(900))
        let historyRecords = cloud.records.filter { $0.id.kind == .history }
        XCTAssertFalse(historyRecords.isEmpty)
        var journal = BrowserSyncJournal(
            deviceID: fixedUUID(971),
            preferences: BrowserSyncPreferences(
                savedStructure: true,
                currentTabs: true,
                historyAndArchive: false,
                extensionSettings: true
            )
        )

        try journal.prepareToOverwriteCloud(
            with: oneSpaceSession(),
            remoteRecords: cloud.records,
            at: fixedDate(1_000)
        )

        for record in historyRecords {
            XCTAssertEqual(
                journal.records.first { $0.id == record.id },
                record,
                "Cloud history was overwritten although history sync is off"
            )
            XCTAssertFalse(journal.pendingRecordIDs.contains(record.id))
        }
    }

    private func oneSpaceSession(
        spaceID: SpaceID? = nil,
        profileID: UUID? = nil,
        tabID: TabID? = nil,
        lastActivatedAt: Date? = nil
    ) -> BrowserSession {
        let resolvedSpaceID = spaceID ?? SpaceID(rawValue: fixedUUID(100))
        let resolvedProfileID = profileID ?? fixedUUID(101)
        let resolvedTabID = tabID ?? TabID(rawValue: fixedUUID(102))
        let resolvedActivation = lastActivatedAt ?? fixedDate(100)
        let tab = BrowserTab(
            id: resolvedTabID,
            title: "Example",
            url: URL(string: "https://example.com"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: resolvedActivation
        )
        let space = BrowserSpace(
            id: resolvedSpaceID,
            profile: BrowsingProfile(id: resolvedProfileID),
            name: "Test",
            symbol: "sparkles",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }

    private func currentTabSession(count: Int) -> BrowserSession {
        let spaceID = SpaceID(rawValue: fixedUUID(700))
        let tabs = (0..<count).map { index in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(701 + index)),
                title: "Tab \(index)",
                url: URL(string: "https://example.com/\(index)"),
                symbol: "globe",
                placement: .current,
                lastActivatedAt: fixedDate(TimeInterval(100 + index))
            )
        }
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: fixedUUID(799)),
            name: "Ordered",
            symbol: "list.number",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs.first?.id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: spaceID)
    }

    /// A one-Space session whose current tabs carry the listed memberships in
    /// the listed order, so a fixture can describe a run, an interrupted run, or
    /// a lone member without going through any mutation path.
    private func splitGroupSession(
        memberships: [SplitGroupID?],
        spaceID: SpaceID? = nil,
        positionModifiedAt: Date? = nil
    ) -> BrowserSession {
        let resolvedSpaceID = spaceID ?? SpaceID(rawValue: fixedUUID(1_100))
        let tabs = memberships.enumerated().map { index, groupID in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(1_101 + index)),
                title: "Split \(index)",
                url: URL(string: "https://example.com/split/\(index)"),
                symbol: "globe",
                placement: .current,
                splitGroupID: groupID,
                lastActivatedAt: fixedDate(TimeInterval(100 + index)),
                positionModifiedAt: positionModifiedAt
            )
        }
        let space = BrowserSpace(
            id: resolvedSpaceID,
            profile: BrowsingProfile(id: fixedUUID(1_119)),
            name: "Split",
            symbol: "rectangle.split.2x1",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs.first?.id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: resolvedSpaceID)
    }

    private func projectedTab(
        _ tabID: TabID,
        in journal: BrowserSyncJournal
    ) -> BrowserSyncTab? {
        journal.records.compactMap { record -> BrowserSyncTab? in
            guard case .tab(let tab)? = record.payload, tab.id == tabID else { return nil }
            return tab
        }.first
    }

    /// The same record as a build that has never heard of split view would have
    /// written it: that build's encoder has no `splitGroupID` key at all.
    private func tabAsAnOlderBuildWroteIt(
        _ tab: BrowserSyncTab
    ) throws -> BrowserSyncTab {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(tab)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "splitGroupID")
        return try JSONDecoder().decode(
            BrowserSyncTab.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func tabOrderTokens(
        in journal: BrowserSyncJournal
    ) -> [TabID: String] {
        Dictionary(
            uniqueKeysWithValues: journal.records.compactMap { record in
                guard case .tab(let tab)? = record.payload else { return nil }
                return (tab.id, tab.orderToken)
            })
    }

    private func syncTab(_ tab: BrowserTab, spaceID: SpaceID) -> BrowserSyncTab {
        BrowserSyncTab(
            id: tab.id,
            spaceID: spaceID,
            title: tab.title,
            url: tab.url,
            symbol: tab.symbol,
            placement: tab.placement,
            folderID: tab.folderID,
            orderToken: "a",
            lastActivatedAt: tab.lastActivatedAt,
            positionModifiedAt: tab.positionModifiedAt
        )
    }

    private func spaceRecord(_ space: BrowserSpace, clock: UInt64) -> BrowserSyncRecord {
        BrowserSyncRecord.save(
            .space(
                BrowserSyncSpace(
                    id: space.id,
                    profileID: space.profile.id,
                    name: space.name,
                    symbol: space.symbol,
                    accent: space.accent,
                    orderToken: "a"
                )),
            version: BrowserSyncVersion(logicalClock: clock, deviceID: fixedUUID(200))
        )
    }

    /// A Space record written by a newer build can name heraldic vocabulary this
    /// build has never seen. Because a payload that refuses to decode fails the
    /// whole fetched batch — not just its own record — the branding decoder has to
    /// absorb the unknown value rather than throw.
    func testSyncedSpaceSurvivesBrandingVocabularyFromANewerBuild() throws {
        var session = BrowserSession.preview
        session.spaces[0].branding = BrowserSpaceBranding(
            colors: [.ink, .ocean, .gold],
            bannerPattern: .chevron,
            iconStyle: .layeredCrest,
            crest: BrowserSpaceCrest(trim: .laurel, symbol: .oak)
        )
        var journal = BrowserSyncJournal(deviceID: fixedUUID(900))
        try journal.stage(session: session, at: fixedDate(100))
        let record = try XCTUnwrap(
            journal.activeRecords.first {
                $0.id
                    == BrowserSyncRecordID(
                        kind: .space,
                        value: session.spaces[0].id.rawValue
                    )
            }
        )
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(try XCTUnwrap(record.payload))
            ) as? [String: Any]
        )
        var space = try XCTUnwrap(payload["value"] as? [String: Any])
        var branding = try XCTUnwrap(space["branding"] as? [String: Any])
        var crest = try XCTUnwrap(branding["crest"] as? [String: Any])
        crest["symbol"] = "griffin"
        crest["trim"] = "mantling"
        branding["crest"] = crest
        branding["renderingVersion"] = 4
        space["branding"] = branding
        payload["value"] = space

        let decoded = try JSONDecoder().decode(
            BrowserSyncPayload.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        guard case .space(let syncedSpace) = decoded else {
            return XCTFail("The Space payload no longer decodes at all.")
        }
        XCTAssertEqual(syncedSpace.branding.crest.symbol, .mountain)
        XCTAssertEqual(syncedSpace.branding.crest.trim, .none)
        // Everything this build does understand still arrives intact.
        XCTAssertEqual(syncedSpace.branding.bannerPattern, .chevron)
        XCTAssertEqual(syncedSpace.branding.colors, [.ink, .ocean, .gold])
        XCTAssertEqual(syncedSpace.name, session.spaces[0].name)
    }

    private func history(id: UUID, path: String) -> BrowserHistoryEntry {
        BrowserHistoryEntry(
            id: id,
            url: URL(string: "https://example.com/\(path)")!,
            title: path,
            firstVisitedAt: fixedDate(10),
            lastVisitedAt: fixedDate(20)
        )
    }

    private func fixedDate(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}

private final class CorruptBrowserSyncJournalPersistence: BrowserSyncJournalPersisting {
    private(set) var savedJournal: BrowserSyncJournal?

    func load() throws -> BrowserSyncJournal? {
        throw BrowserSyncJournalPersistenceError.decodingFailed
    }

    func save(_ journal: BrowserSyncJournal) throws {
        savedJournal = journal
    }
}

private final class FailingSaveBrowserSyncJournalPersistence: BrowserSyncJournalPersisting {
    enum Failure: Error {
        case save
    }

    func load() throws -> BrowserSyncJournal? { nil }

    func save(_ journal: BrowserSyncJournal) throws {
        throw Failure.save
    }
}
