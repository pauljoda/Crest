import Foundation
import XCTest

@testable import Crest

final class BrowserSyncTests: XCTestCase {
    func testBlankPageAllowanceDoesNotPermitOtherNonWebSyncURLs() throws {
        let session = oneSpaceSession()
        var tab = syncTab(session.spaces[0].tabs[0], spaceID: session.spaces[0].id)
        for value in [
            "file:///private/secret", "javascript:alert(1)", "data:text/html,hello", "about:config",
            "about:blank?script=1",
        ] {
            tab.url = URL(string: value)
            XCTAssertThrowsError(try BrowserSyncPayload.tab(tab).validate())
        }
    }

    func testHostileOrderTokensFailClosed() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.spaces.first)
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

    func testLegacySyncFolderWithoutCollapseStateDefaultsToExpanded() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.spaces.first)
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

    func testLegacySyncSpaceWithoutBrowsingPreferencesUsesDefaults() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.spaces.first)
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
        let space = try XCTUnwrap(session.spaces.first)
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

    func testLegacySyncTabWithoutPositionTimestampStillDecodes() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.spaces.first)
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

    func testLegacySyncTabWithoutRenameFieldsStillDecodes() throws {
        let session = oneSpaceSession()
        let space = try XCTUnwrap(session.spaces.first)
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
        let space = try XCTUnwrap(session.spaces.first)
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

    func testArchivePayloadCarryingSplitMembershipFailsValidation() throws {
        let groupID = SplitGroupID(rawValue: fixedUUID(1_170))
        let session = splitGroupSession(memberships: [groupID, groupID])
        let space = try XCTUnwrap(session.spaces.first)
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
            tabs: [tab]
        )
        return BrowserSession(spaces: [space])
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
            tabs: tabs
        )
        return BrowserSession(spaces: [space])
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

    /// A Space record written by a newer build can name heraldic vocabulary this
    /// build has never seen. The branding decoder must keep the readable Space
    /// data instead of losing the record to an unknown decorative value.
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
        crest["symbol"] = "__unknown_future_symbol__"
        crest["trim"] = "__unknown_future_trim__"
        branding["crest"] = crest
        branding["renderingVersion"] = BrowserSpaceBranding.currentRenderingVersion + 1
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

    private func fixedDate(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}

/// TRANSITIONAL until slice 8c ports the journal contract tests to the core: a
/// device whose file holds a session and its journal, opened as a launch opens
/// it, which takes cloud records through its core as the transport does.
@MainActor
final class BrowserSyncingDevice {
    // MARK: - Variables

    let harness: BrowserStoredSessionHarness

    /// The session the device's store shows.
    var session: BrowserSession { harness.store.session }

    /// The journal the device's core accepted last, as its file holds it.
    var journal: BrowserSyncJournal {
        do { return try harness.storedJournal() } catch {
            preconditionFailure("A session the core keeps in its file always has a journal there: \(error)")
        }
    }

    // MARK: - Initializers

    /// A device whose file holds `session` and `journal`.
    init(_ session: BrowserSession, journal: BrowserSyncJournal) throws {
        harness = try BrowserStoredSessionHarness(session: session, journal: journal)
    }

    /// A device whose file holds `session`, which its journal from `deviceID`
    /// staged at `date`.
    convenience init(_ session: BrowserSession, deviceID: UUID = UUID(), stagedAt date: Date) throws {
        var journal = BrowserSyncJournal(deviceID: deviceID)
        try journal.stage(session: session, at: date)
        try self.init(session, journal: journal)
    }

    // MARK: - Actions

    /// Merges `records` from the cloud, and answers the session the store
    /// shows then.
    @discardableResult
    func merge(_ records: [BrowserSyncRecord]) throws -> BrowserSession {
        try harness.deliverNow(MergeSyncRecords(records: records.map(SyncRecord.init(browser:))))
        return session
    }

    /// Replaces the session with what the cloud holds, and answers the
    /// session the store shows then.
    func replace(with records: [BrowserSyncRecord]) throws -> BrowserSession {
        try harness.deliverNow(ReplaceWithCloudRecords(records: records.map(SyncRecord.init(browser:))))
        return session
    }

    /// Rebases the journal above what the cloud holds.
    func overwrite(with records: [BrowserSyncRecord]) throws {
        try harness.deliverNow(OverwriteCloud(records: records.map(SyncRecord.init(browser:))))
    }

    /// Acknowledges `recordIDs` as uploaded, at the versions the journal
    /// holds them at.
    func markUploaded(_ recordIDs: Set<BrowserSyncRecordID>) throws {
        let uploaded = journal.records.filter { recordIDs.contains($0.id) }.map {
            UploadedRecord(
                record: SyncRecordReference(kind: SyncRecordKind(browser: $0.id.kind), id: $0.id.value),
                version: SyncVersion(clock: $0.version.logicalClock, deviceID: $0.version.deviceID))
        }
        try harness.deliverNow(AcknowledgeUploads(records: uploaded))
    }
}
