import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserDataRetentionTests: XCTestCase {
    func testHistoryRangeDeletionUsesLastVisitAndHalfOpenBoundsWithinItsSpace() throws {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let end = start.addingTimeInterval(10)
        var session = BrowserSession.preview
        let spaceID = session.spaces[0].id
        session.spaces[0].history = [
            Self.history(title: "Before", visitedAt: start.addingTimeInterval(-1)),
            Self.history(title: "Start", visitedAt: start),
            Self.history(title: "Inside", visitedAt: end.addingTimeInterval(-1)),
            Self.history(title: "End", visitedAt: end),
        ]
        session.spaces[1].history = [Self.history(title: "Other Space", visitedAt: start)]
        let browser = BrowserStore(session: session)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(browser.session.space(id: spaceID)))

        XCTAssertTrue(browser.deleteHistory(from: start, until: end, matching: assignment))
        XCTAssertEqual(browser.session.spaces[0].history.map(\.title), ["Before", "End"])
        XCTAssertEqual(browser.session.spaces[1].history.map(\.title), ["Other Space"])
        XCTAssertFalse(browser.deleteHistory(from: end, until: start, matching: assignment))
    }

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

    func testSessionCleanupAppliesEachSpacesOwnHistoryAndArchiveWindows() throws {
        let now = Date.now
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

        let browser = BrowserStore(session: session)

        browser.sweepExpiredBrowsingData()
        let swept = browser.session
        XCTAssertEqual(
            try XCTUnwrap(swept.space(id: cleanedSpaceID)).history.map(\.title),
            ["Recent"]
        )
        XCTAssertEqual(
            try XCTUnwrap(swept.space(id: cleanedSpaceID)).archivedTabs.map(\.tab.title),
            ["Recent"]
        )
        XCTAssertEqual(
            try XCTUnwrap(swept.space(id: untouchedSpaceID)).history.map(\.title),
            ["Other Space"]
        )
        XCTAssertEqual(
            try XCTUnwrap(swept.space(id: untouchedSpaceID)).archivedTabs.map(\.tab.title),
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
        var journal = BrowserSyncJournal()
        try journal.stage(session: session, at: oldDate)
        let harness = try BrowserStoredSessionHarness(session: session, journal: journal)
        let browser = harness.store
        let sync = try XCTUnwrap(browser.syncCoordinator)

        browser.updateDataRetentionPreferences(
            .init(
                history: .thirtyDays,
                archive: .thirtyDays,
                downloads: .forever
            ),
            in: spaceID
        )
        await browser.flushPendingSyncPersistence()

        let savedSpace = try XCTUnwrap(browser.session.space(id: spaceID))
        XCTAssertTrue(savedSpace.history.isEmpty)
        XCTAssertTrue(savedSpace.archivedTabs.isEmpty)
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

    func testDownloadCenterSweepUsesSpacePoliciesAndDeterministicSpacing() {
        let now = Date(timeIntervalSinceReferenceDate: 60_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        var session = BrowserSession.preview
        let cleanedProfileID = session.spaces[0].profile.id
        session.spaces[0].browsingPreferences.dataRetention.downloads = .thirtyDays
        let center = BrowserDownloadCenter()
        let expiredID = center.begin(
            profileID: cleanedProfileID,
            filename: "expired.pdf",
            createdAt: oldDate
        )
        center.send(FinishDownload(downloadID: expiredID, finalByteCount: nil))

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
