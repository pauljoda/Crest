import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserDataRetentionTests: XCTestCase {
    func testLegacyBrowsingPreferencesKeepEveryStoredCategoryForever() throws {
        let encoded = try JSONEncoder().encode(BrowserSpaceBrowsingPreferences.default)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "dataRetention")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            BrowserSpaceBrowsingPreferences.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.dataRetention, .default)
        XCTAssertEqual(decoded.dataRetention.history, .forever)
        XCTAssertEqual(decoded.dataRetention.archive, .forever)
        XCTAssertEqual(decoded.dataRetention.downloads, .forever)
    }

    func testRetentionChoicesIncludeShortLongThirtyDayAndForeverWindows() {
        XCTAssertEqual(
            BrowserDataRetentionDuration.allCases,
            [.oneDay, .oneWeek, .thirtyDays, .ninetyDays, .oneYear, .forever]
        )
        XCTAssertEqual(BrowserDataRetentionDuration.thirtyDays.lifetime, 30 * 24 * 60 * 60)
        XCTAssertNil(BrowserDataRetentionDuration.forever.lifetime)
    }

    func testSessionCleanupAppliesEachSpacesOwnHistoryAndArchiveWindows() throws {
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        let recentDate = now.addingTimeInterval(-(29 * 24 * 60 * 60))
        var session = BrowserSession.preview
        let cleanedSpaceID = session.spaces[0].id
        let untouchedSpaceID = session.spaces[1].id
        session.spaces[0].browsingPreferences.dataRetention = .init(
            history: .thirtyDays,
            archive: .thirtyDays,
            downloads: .forever
        )
        session.spaces[1].browsingPreferences.dataRetention = .default
        session.spaces[0].history = [
            Self.history(title: "Old", visitedAt: oldDate),
            Self.history(title: "Recent", visitedAt: recentDate),
        ]
        session.spaces[1].history = [Self.history(title: "Other Space", visitedAt: oldDate)]
        session.spaces[0].archivedTabs = [
            Self.archive(title: "Old", archivedAt: oldDate),
            Self.archive(title: "Recent", archivedAt: recentDate),
        ]
        session.spaces[1].archivedTabs = [
            Self.archive(title: "Other Space", archivedAt: oldDate)
        ]

        let removedRecords = session.applyDataRetentionPolicies(now: now)

        XCTAssertTrue(removedRecords)
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: cleanedSpaceID)).history.map(\.title),
            ["Recent"]
        )
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: cleanedSpaceID)).archivedTabs.map(\.tab.title),
            ["Recent"]
        )
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: untouchedSpaceID)).history.map(\.title),
            ["Other Space"]
        )
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: untouchedSpaceID)).archivedTabs.map(\.tab.title),
            ["Other Space"]
        )
    }

    func testShorteningRetentionImmediatelyDeletesExistingRecordsAndStagesTombstones() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 20_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        var session = BrowserSession.preview
        let spaceID = session.spaces[0].id
        let oldHistory = Self.history(title: "Expired", visitedAt: oldDate)
        let oldArchive = Self.archive(title: "Expired", archivedAt: oldDate)
        session.spaces[0].history = [oldHistory]
        session.spaces[0].archivedTabs = [oldArchive]
        let persistence = InMemoryBrowserSessionPersistence()
        let sync = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence()
        )
        try sync.stage(session: session, at: oldDate)
        let browser = BrowserStore(
            session: session,
            persistence: persistence,
            syncCoordinator: sync,
            syncCoalescingDelay: .zero
        )

        browser.updateDataRetentionPreferences(
            .init(
                history: .thirtyDays,
                archive: .thirtyDays,
                downloads: .forever
            ),
            in: spaceID,
            now: now
        )
        await browser.flushPendingSyncPersistence()

        let savedSpace = try XCTUnwrap(persistence.session?.space(id: spaceID))
        XCTAssertTrue(savedSpace.history.isEmpty)
        XCTAssertTrue(savedSpace.archivedTabs.isEmpty)
        XCTAssertEqual(persistence.savedScopes.last, .everything)
        for recordID in [
            BrowserSyncRecordID(kind: .history, value: oldHistory.id),
            BrowserSyncRecordID(kind: .archive, value: oldArchive.id.rawValue),
        ] {
            let record = try XCTUnwrap(
                sync.journal.records.first(where: { $0.id == recordID })
            )
            XCTAssertEqual(record.tombstone?.reason, .retention)
        }
    }

    func testExpiredSyncedHistoryCannotReappearAfterMerge() throws {
        let now = Date(timeIntervalSinceReferenceDate: 30_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        var remoteSession = BrowserSession.preview
        let spaceID = remoteSession.spaces[0].id
        let history = Self.history(title: "Expired Remote", visitedAt: oldDate)
        remoteSession.spaces[0].browsingPreferences.dataRetention.history = .thirtyDays
        remoteSession.spaces[0].history = [history]
        var remoteJournal = BrowserSyncJournal()
        try remoteJournal.stage(session: remoteSession, at: oldDate)
        var localSession = remoteSession
        localSession.spaces[0].history = []
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence()
        )

        let merged = try coordinator.merge(
            remoteRecords: remoteJournal.records,
            into: localSession,
            at: now
        )

        XCTAssertTrue(try XCTUnwrap(merged.space(id: spaceID)).history.isEmpty)
        let recordID = BrowserSyncRecordID(kind: .history, value: history.id)
        let record = try XCTUnwrap(
            coordinator.journal.records.first(where: { $0.id == recordID })
        )
        XCTAssertEqual(record.tombstone?.reason, .retention)
    }

    func testDownloadCleanupIsProfileScopedAndPreservesActiveTransfers() throws {
        let now = Date(timeIntervalSinceReferenceDate: 40_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        let retainedProfileID = UUID()
        let cleanedProfileID = UUID()
        var ledger = BrowserDownloadLedger()
        let expiredFinishedID = ledger.begin(
            profileID: cleanedProfileID,
            filename: "expired.pdf",
            createdAt: oldDate
        )
        ledger.finish(expiredFinishedID)
        let activeID = ledger.begin(
            profileID: cleanedProfileID,
            filename: "active.pdf",
            createdAt: oldDate
        )
        ledger.setProgress(0.5, for: activeID)
        let otherProfileID = ledger.begin(
            profileID: retainedProfileID,
            filename: "other.pdf",
            createdAt: oldDate
        )
        ledger.finish(otherProfileID)

        let removed = ledger.removeExpiredRecords(
            retentionByProfileID: [cleanedProfileID: .thirtyDays],
            now: now
        )

        XCTAssertEqual(removed, [expiredFinishedID])
        XCTAssertEqual(ledger.items(for: cleanedProfileID).map(\.id), [activeID])
        XCTAssertEqual(ledger.items(for: retainedProfileID).map(\.id), [otherProfileID])
    }

    func testActiveSceneSweepAppliesHistoryAndArchiveRetention() throws {
        let now = Date(timeIntervalSinceReferenceDate: 50_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        var session = BrowserSession.preview
        let spaceID = session.spaces[0].id
        session.spaces[0].browsingPreferences.dataRetention = .init(
            history: .thirtyDays,
            archive: .thirtyDays,
            downloads: .forever
        )
        session.spaces[0].history = [Self.history(title: "Expired", visitedAt: oldDate)]
        session.spaces[0].archivedTabs = [
            Self.archive(title: "Expired", archivedAt: oldDate)
        ]
        let persistence = InMemoryBrowserSessionPersistence()
        let browser = BrowserStore(session: session, persistence: persistence)

        XCTAssertTrue(browser.sweepExpiredBrowsingData(now: now))

        let sweptSpace = try XCTUnwrap(browser.session.space(id: spaceID))
        XCTAssertTrue(sweptSpace.history.isEmpty)
        XCTAssertTrue(sweptSpace.archivedTabs.isEmpty)
        XCTAssertEqual(persistence.savedScopes.last, .everything)
    }

    func testDownloadCenterSweepUsesSpacePoliciesAndDeterministicSpacing() {
        let now = Date(timeIntervalSinceReferenceDate: 60_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        var session = BrowserSession.preview
        let cleanedProfileID = session.spaces[0].profile.id
        session.spaces[0].browsingPreferences.dataRetention.downloads = .thirtyDays
        var ledger = BrowserDownloadLedger()
        let expiredID = ledger.begin(
            profileID: cleanedProfileID,
            filename: "expired.pdf",
            createdAt: oldDate
        )
        ledger.finish(expiredID)
        let center = BrowserDownloadCenter(ledger: ledger)

        XCTAssertTrue(center.sweepExpiredRecords(using: session, now: now))
        XCTAssertTrue(center.items.isEmpty)
        XCTAssertFalse(
            center.sweepExpiredRecords(
                using: session,
                now: now.addingTimeInterval(
                    BrowserCurrentTabCleanupSchedule.minimumSweepSpacing - 1
                )
            )
        )
        XCTAssertTrue(
            center.sweepExpiredRecords(
                using: session,
                now: now.addingTimeInterval(
                    BrowserCurrentTabCleanupSchedule.minimumSweepSpacing
                )
            )
        )
    }

    func testShorterRetentionNeedsConfirmationButLongerRetentionDoesNot() {
        XCTAssertTrue(
            BrowserDataRetentionChange(
                category: .history,
                previous: .forever,
                proposed: .thirtyDays
            ).requiresConfirmation
        )
        XCTAssertTrue(
            BrowserDataRetentionChange(
                category: .archive,
                previous: .oneYear,
                proposed: .ninetyDays
            ).requiresConfirmation
        )
        XCTAssertFalse(
            BrowserDataRetentionChange(
                category: .downloads,
                previous: .thirtyDays,
                proposed: .oneYear
            ).requiresConfirmation
        )
    }

    private static func history(title: String, visitedAt: Date) -> BrowserHistoryEntry {
        BrowserHistoryEntry(
            url: URL(string: "https://\(title.lowercased().replacingOccurrences(of: " ", with: "-")).example")!,
            title: title,
            firstVisitedAt: visitedAt,
            lastVisitedAt: visitedAt
        )
    }

    private static func archive(title: String, archivedAt: Date) -> ArchivedTab {
        ArchivedTab(
            tab: BrowserTab(
                title: title,
                url: URL(string: "https://\(title.lowercased().replacingOccurrences(of: " ", with: "-")).example"),
                placement: .current,
                lastActivatedAt: archivedAt
            ),
            archivedAt: archivedAt,
            reason: .closed
        )
    }
}
