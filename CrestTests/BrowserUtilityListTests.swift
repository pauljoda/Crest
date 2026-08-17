import Foundation
import XCTest

@testable import Crest

final class BrowserUtilityListTests: XCTestCase {
    func testDownloadProgressPublishingCoalescesTinyChangesButKeepsCompletion() {
        XCTAssertFalse(
            BrowserDownloadProgressPolicy.shouldPublish(previous: 0.4, next: 0.405)
        )
        XCTAssertTrue(
            BrowserDownloadProgressPolicy.shouldPublish(previous: 0.4, next: 0.42)
        )
        XCTAssertTrue(
            BrowserDownloadProgressPolicy.shouldPublish(previous: 0.995, next: 1)
        )
    }

    func testDownloadProgressDoesNotRestartUtilitySectionPreparation() {
        let id = UUID()
        let profileID = UUID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(rawValue: UUID()),
            profileID: profileID
        )
        let initial = BrowserDownloadItem(
            id: id,
            profileID: profileID,
            createdAt: .now,
            filename: "Crest.dmg",
            destinationURL: nil,
            progress: 0.1,
            state: .downloading,
            riskAssessment: nil
        )
        var progressed = initial
        progressed.progress = 0.9
        var finished = progressed
        finished.state = .finished

        let initialRequest = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: assignment,
            archivedTabs: [],
            history: [],
            downloads: [initial],
            searchText: "",
            filter: .all
        )
        let progressRequest = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: assignment,
            archivedTabs: [],
            history: [],
            downloads: [progressed],
            searchText: "",
            filter: .all
        )
        let finishedRequest = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: assignment,
            archivedTabs: [],
            history: [],
            downloads: [finished],
            searchText: "",
            filter: .all
        )

        XCTAssertEqual(initialRequest, progressRequest)
        XCTAssertNotEqual(initialRequest, finishedRequest)
    }

    func testUtilityPreparationIdentityIncludesTheExactSpaceProfileAssignment() {
        let spaceID = SpaceID(
            rawValue: UUID(
                uuid: (
                    0x43, 0x52, 0x45, 0x53, 0x54, 0x55, 0x54, 0x49,
                    0x4C, 0x49, 0x54, 0x59, 0x53, 0x50, 0x41, 0x43
                )))
        let first = BrowserUtilityListRequest(
            surface: .history,
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID(
                    uuid: (
                        0x43, 0x52, 0x45, 0x53, 0x54, 0x55, 0x54, 0x49,
                        0x4C, 0x49, 0x54, 0x59, 0x50, 0x52, 0x4F, 0x31
                    ))
            ),
            archivedTabs: [],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )
        let replacement = BrowserUtilityListRequest(
            surface: .history,
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID(
                    uuid: (
                        0x43, 0x52, 0x45, 0x53, 0x54, 0x55, 0x54, 0x49,
                        0x4C, 0x49, 0x54, 0x59, 0x50, 0x52, 0x4F, 0x32
                    ))
            ),
            archivedTabs: [],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )

        XCTAssertNotEqual(first, replacement)
        XCTAssertFalse(first.hasSamePresentationOwnership(as: replacement))
    }

    func testDownloadReconciliationUsesLiveProgressWithoutSynthesizingRows() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.1,
            state: .downloading
        )
        let current = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.82,
            state: .downloading
        )
        let newlyArrived = utilityDownload(
            id: identifier(0x65),
            profileID: context.assignment.profileID,
            progress: 0.3,
            state: .downloading
        )

        let sections = BrowserUtilityListReconciliation.sections(
            preparedSections: [context.section(prepared)],
            surface: .downloads,
            assignment: context.assignment,
            downloads: [current, newlyArrived],
            searchText: "",
            filter: .all
        )

        let item = try XCTUnwrap(sections.first?.items.first)
        guard case .download(let download) = item else {
            return XCTFail("Expected a reconciled download")
        }
        XCTAssertEqual(download.id, context.itemID)
        XCTAssertEqual(download.progress, 0.82)
        XCTAssertEqual(sections.flatMap(\.items).count, 1)
    }

    func testDownloadReconciliationImmediatelyAppliesCurrentFilterState() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.8,
            state: .downloading
        )
        let finished = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 1,
            state: .finished
        )
        let preparedSections = [context.section(prepared)]

        XCTAssertTrue(
            BrowserUtilityListReconciliation.sections(
                preparedSections: preparedSections,
                surface: .downloads,
                assignment: context.assignment,
                downloads: [finished],
                searchText: "",
                filter: .downloadsInProgress
            ).isEmpty
        )

        let allSections = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [finished],
            searchText: "",
            filter: .all
        )
        let item = try XCTUnwrap(allSections.first?.items.first)
        guard case .download(let current) = item else {
            return XCTFail("Expected a current download")
        }
        XCTAssertEqual(current.state, .finished)
    }

    func testDownloadReconciliationDropsRemovedAndForeignProfileRows() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.2,
            state: .downloading
        )
        let foreign = utilityDownload(
            id: context.itemID,
            profileID: identifier(0x66),
            progress: 0.9,
            state: .finished
        )
        let exact = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.4,
            state: .downloading
        )
        let preparedSections = [context.section(prepared)]

        for current in [[], [foreign]] {
            XCTAssertTrue(
                BrowserUtilityListReconciliation.sections(
                    preparedSections: preparedSections,
                    surface: .downloads,
                    assignment: context.assignment,
                    downloads: current,
                    searchText: "",
                    filter: .all
                ).isEmpty
            )
        }

        let reconciled = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [foreign, exact, foreign],
            searchText: "",
            filter: .all
        )
        let item = try XCTUnwrap(reconciled.first?.items.first)
        guard case .download(let current) = item else {
            return XCTFail("Expected the exact-profile download")
        }
        XCTAssertEqual(current.profileID, context.assignment.profileID)
        XCTAssertEqual(current.progress, 0.4)
    }

    func testDownloadReconciliationEmitsDuplicatePreparedIDsOnce() throws {
        let context = utilityDownloadContext()
        let foreign = utilityDownload(
            id: context.itemID,
            profileID: identifier(0x66),
            progress: 0.1,
            state: .downloading
        )
        let exact = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.7,
            state: .downloading
        )
        let preparedSections = [
            context.section(foreign),
            context.section(exact),
        ]

        let request = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: context.assignment,
            archivedTabs: [],
            history: [],
            downloads: [foreign, exact, exact],
            searchText: "",
            filter: .all
        )
        XCTAssertEqual(request.downloads.map(\.id), [context.itemID])
        XCTAssertEqual(request.downloads.first?.profileID, context.assignment.profileID)

        let reconciled = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [foreign, exact, exact],
            searchText: "",
            filter: .all
        )
        let items = reconciled.flatMap(\.items)
        XCTAssertEqual(items.count, 1)
        guard case .download(let current) = try XCTUnwrap(items.first) else {
            return XCTFail("Expected one exact-profile download")
        }
        XCTAssertEqual(current.profileID, context.assignment.profileID)
        XCTAssertEqual(current.progress, 0.7)
    }

    func testEmptyPresentationNormalizesWhitespaceAndTrimmedQueries() {
        let english = Locale(identifier: "en")
        let whitespace = BrowserUtilityListEmptyPresentation(
            surface: .history,
            searchText: "   \n  ",
            filter: .all
        )
        XCTAssertEqual(localized(whitespace.title, locale: english), "No History")
        XCTAssertEqual(whitespace.systemImage, BrowserUtilitySurface.history.systemImage)

        let filteredWhitespace = BrowserUtilityListEmptyPresentation(
            surface: .downloads,
            searchText: "  ",
            filter: .downloadsNeedsAttention
        )
        XCTAssertEqual(
            localized(filteredWhitespace.description, locale: english),
            "No items match the selected filter."
        )

        let query = BrowserUtilityListEmptyPresentation(
            surface: .archive,
            searchText: "  Crest  ",
            filter: .all
        )
        XCTAssertEqual(localized(query.title, locale: english), "No Results")
        XCTAssertEqual(
            localized(query.description, locale: english),
            "No archived tabs in this Space match “Crest”."
        )
    }

    func testUtilityPreparationRefreshesAtTheNextRelevantBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-08-08T00:00:00Z"))
        let visitDate = try XCTUnwrap(
            formatter.date(from: "2026-08-01T15:00:00Z")
        )
        let entry = BrowserHistoryEntry(
            id: identifier(0x67),
            url: URL(filePath: "/crest-preview/history"),
            title: "History",
            firstVisitedAt: visitDate,
            lastVisitedAt: visitDate
        )
        let request = BrowserUtilityListRequest(
            surface: .history,
            assignment: utilityDownloadContext().assignment,
            archivedTabs: [],
            history: [entry],
            downloads: [],
            searchText: "",
            filter: .historyPastWeek
        )

        XCTAssertEqual(
            BrowserUtilityListPreparation.nextRefreshDate(
                for: request,
                now: now,
                calendar: calendar
            ),
            try XCTUnwrap(formatter.date(from: "2026-08-08T15:00:00Z"))
        )

        let emptyRequest = BrowserUtilityListRequest(
            surface: .history,
            assignment: utilityDownloadContext().assignment,
            archivedTabs: [],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )
        XCTAssertNil(
            BrowserUtilityListPreparation.nextRefreshDate(
                for: emptyRequest,
                now: now,
                calendar: calendar
            )
        )
    }

    func testUtilityRowIdentifiersAndProgressNormalizationAreStable() {
        let id = identifier(0x68)
        XCTAssertEqual(
            BrowserUtilityAccessibilityID.historyRow(id),
            "history-utility-row-00000000-0000-4000-8000-000000000068"
        )
        XCTAssertEqual(
            BrowserUtilityAccessibilityID.downloadRow(id),
            "downloads-utility-row-00000000-0000-4000-8000-000000000068"
        )
        XCTAssertEqual(BrowserDownloadProgressPolicy.normalized(-0.4), 0)
        XCTAssertEqual(BrowserDownloadProgressPolicy.normalized(1.4), 1)
    }

    func testUtilityMetadataRemainsDeferredAndResolvesInEnglishAndArabic() {
        let english = Locale(identifier: "en")
        let arabic = Locale(identifier: "ar")
        let expectations: [(LocalizedStringResource, String, String)] = [
            (BrowserUtilitySurface.archive.title, "Archive", "الأرشيف"),
            (
                BrowserUtilitySurface.history.searchPrompt,
                "Search History…",
                "البحث في السجل…"
            ),
            (
                BrowserUtilitySurface.downloads.emptyTitle,
                "No Downloads",
                "لا توجد تنزيلات"
            ),
            (
                BrowserUtilitySurface.history.emptyDescription,
                "Completed visits from this Space appear here and remain "
                    + "separate from every other Space.",
                "تظهر هنا الزيارات المكتملة من هذه المساحة وتظل منفصلة "
                    + "عن كل مساحة أخرى."
            ),
            (
                BrowserUtilitySurface.archive.noResultsDescription(
                    matching: "Example"
                ),
                "No archived tabs in this Space match “Example”.",
                "لا توجد علامات تبويب مؤرشفة في هذه المساحة تطابق «Example»."
            ),
            (
                BrowserUtilitySurface.downloads.filterLabel,
                "Filter Downloads",
                "فلترة التنزيلات"
            ),
            (
                BrowserUtilityListFilter.archivedAutomatically.title,
                "Automatically Cleaned",
                "المنظفة تلقائيًا"
            ),
            (
                BrowserUtilityListFilter.archivedSynced.title,
                "Synced from Another Device",
                "متزامنة من جهاز آخر"
            ),
            (
                BrowserUtilityListFilter.downloadsNeedsAttention.title,
                "Needs Attention",
                "تحتاج إلى انتباه"
            ),
            (
                BrowserUtilityDownloadDestination.open.title,
                "Open",
                "فتح"
            ),
            (
                BrowserUtilityDownloadDestination.revealInFinder.title,
                "Show in Finder",
                "إظهار في Finder"
            ),
            (
                BrowserUtilityDownloadDestination.files.title,
                "Save to Files…",
                "حفظ في الملفات…"
            ),
            (
                BrowserUtilityPresentation.noFilteredItemsDescription,
                "No items match the selected filter.",
                "لا توجد عناصر تطابق عامل التصفية المحدد."
            ),
        ]

        for (resource, englishValue, arabicValue) in expectations {
            XCTAssertEqual(localized(resource, locale: english), englishValue)
            XCTAssertEqual(localized(resource, locale: arabic), arabicValue)
        }
    }

    func testCommonListSwitcherKeepsTheThreeRequestedDestinationsInOrder() {
        XCTAssertEqual(
            BrowserUtilitySwitcherLayout.destinations,
            [.archive, .history, .downloads]
        )
        XCTAssertEqual(
            BrowserUtilitySwitcherLayout.destinations.enumerated().map {
                BrowserUtilitySwitcherLayout.verticalOffset(
                    for: $0.offset,
                    count: BrowserUtilitySwitcherLayout.destinations.count
                )
            },
            [-64, 0, 64]
        )
        XCTAssertEqual(BrowserUtilitySwitcherLayout.buttonSize, 44)
        XCTAssertEqual(BrowserUtilitySwitcherLayout.collapsedScale, 0.08)
        XCTAssertEqual(BrowserUtilitySwitcherLayout.spacing, 0)
        XCTAssertEqual(BrowserUtilitySwitcherLayout.destinationGap, 18)
        XCTAssertEqual(
            BrowserUtilitySwitcherLayout.expansionDelay(for: 0),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BrowserUtilitySwitcherLayout.expansionDelay(for: 2),
            0.09,
            accuracy: 0.001
        )
    }

    func testRelativeTimeSectionsResolveForEnglishAndArabic() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")
        )
        let english = Locale(identifier: "en")
        let arabic = Locale(identifier: "ar")

        let cases: [(String, String, String)] = [
            ("2026-08-07T09:00:00Z", "Today", "اليوم"),
            ("2026-08-06T09:00:00Z", "1 day ago", "قبل يوم واحد"),
            ("2026-08-05T09:00:00Z", "2 days ago", "قبل يومين"),
            ("2026-08-04T09:00:00Z", "3 days ago", "قبل 3 أيام"),
            ("2026-07-29T09:00:00Z", "1 week ago", "قبل أسبوع واحد"),
            ("2026-07-20T09:00:00Z", "2 weeks ago", "قبل أسبوعين"),
            ("2026-07-13T09:00:00Z", "3 weeks ago", "قبل 3 أسابيع"),
        ]

        for (timestamp, englishLabel, arabicLabel) in cases {
            let date = try XCTUnwrap(ISO8601DateFormatter().date(from: timestamp))
            let section = BrowserUtilityTimeSection(
                date: date,
                now: now,
                calendar: calendar
            )
            XCTAssertEqual(
                localized(section.title, locale: english),
                englishLabel
            )
            XCTAssertEqual(
                localized(section.title, locale: arabic),
                arabicLabel
            )
        }
    }

    func testOlderTimeSectionFormatsItsMonthForTheRequestedLocale() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")
        )
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-06-15T09:00:00Z")
        )
        let section = BrowserUtilityTimeSection(
            date: date,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            localized(section.title, locale: Locale(identifier: "en")),
            "June 2026"
        )
        XCTAssertEqual(
            localized(section.title, locale: Locale(identifier: "ar")),
            "يونيو 2026"
        )
    }

    func testUtilityCountsUseLocalizedPluralForms() {
        let english = Locale(identifier: "en")
        let arabic = Locale(identifier: "ar")

        XCTAssertEqual(
            localized(
                BrowserUtilityPresentation.downloadCount(1),
                locale: english
            ),
            "1 download"
        )
        XCTAssertEqual(
            localized(
                BrowserUtilityPresentation.downloadCount(2),
                locale: arabic
            ),
            "تنزيلان"
        )
        XCTAssertEqual(
            localized(
                BrowserUtilityPresentation.historyVisits(
                    host: "example.com",
                    count: 3
                ),
                locale: arabic
            ),
            "example.com · 3 زيارات"
        )
    }

    func testDownloadLedgerRetainsTheTimeUsedForListGrouping() {
        var ledger = BrowserDownloadLedger()
        let createdAt = Date(timeIntervalSince1970: 1_786_084_200)

        _ = ledger.begin(
            profileID: UUID(),
            filename: "crest.dmg",
            createdAt: createdAt
        )

        XCTAssertEqual(ledger.items.first?.createdAt, createdAt)
    }

    func testUtilitySectionsArePreparedAwayFromTheRenderPass() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")
        )
        let today = BrowserHistoryEntry(
            url: try XCTUnwrap(URL(string: "https://example.com/today")),
            title: "Today",
            firstVisitedAt: now,
            lastVisitedAt: now
        )
        let yesterdayDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: now)
        )
        let yesterday = BrowserHistoryEntry(
            url: try XCTUnwrap(URL(string: "https://example.com/yesterday")),
            title: "Yesterday",
            firstVisitedAt: yesterdayDate,
            lastVisitedAt: yesterdayDate
        )
        let request = BrowserUtilityListRequest(
            surface: .history,
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(rawValue: UUID()),
                profileID: UUID()
            ),
            archivedTabs: [],
            history: [yesterday, today],
            downloads: [],
            searchText: "",
            filter: .all
        )

        let sections = await Task.detached(priority: .userInitiated) {
            BrowserUtilityListPreparation.sections(
                for: request,
                now: now,
                calendar: calendar
            )
        }.value

        XCTAssertEqual(
            sections.map {
                localized($0.timeframe.title, locale: Locale(identifier: "en"))
            },
            ["Today", "1 day ago"]
        )
        XCTAssertEqual(sections.flatMap(\.items).count, 2)
    }

    @MainActor
    func testHistoryUsesTheSharedSidebarUtilityPresentation() {
        let chrome = BrowserChromeState()

        chrome.presentHistory()

        XCTAssertEqual(chrome.utilityPresentation.surface, .history)
        XCTAssertTrue(chrome.utilityPresentation.isSwitcherExpanded)

        chrome.utilityPresentation.toggleSwitcher()

        XCTAssertNil(chrome.utilityPresentation.surface)
        XCTAssertFalse(chrome.utilityPresentation.isSwitcherExpanded)
    }

    @MainActor
    func testOpeningTheCommonListTriggerSelectsArchive() {
        let presentation = BrowserUtilityPresentationState()

        presentation.toggleSwitcher()

        XCTAssertTrue(presentation.isSwitcherExpanded)
        XCTAssertEqual(presentation.surface, .archive)
    }

    @MainActor
    func testCommonListTriggerCanRouteANewDownloadNotificationToDownloads() {
        let presentation = BrowserUtilityPresentationState()

        presentation.toggleSwitcher(preferredSurface: .downloads)

        XCTAssertTrue(presentation.isSwitcherExpanded)
        XCTAssertEqual(presentation.surface, .downloads)
    }

    func testDownloadNotificationUsesTheNewestActiveTransferProgress() throws {
        let profileID = identifier(0x70)
        let older = BrowserDownloadItem(
            id: identifier(0x71),
            profileID: profileID,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            filename: "older.zip",
            destinationURL: nil,
            progress: 0.8,
            state: .downloading,
            riskAssessment: nil
        )
        let newest = BrowserDownloadItem(
            id: identifier(0x72),
            profileID: profileID,
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            filename: "newest.pdf",
            destinationURL: nil,
            progress: 0.35,
            state: .downloading,
            riskAssessment: nil
        )

        XCTAssertEqual(
            try XCTUnwrap(
                BrowserDownloadNotificationPolicy.progress(in: [older, newest])
            ),
            0.35,
            accuracy: 0.001
        )
    }

    func testDownloadFileIconsReflectCommonFileKinds() {
        let expectations = [
            ("Crest.pdf", "doc.richtext.fill"),
            ("Screenshot.png", "photo.fill"),
            ("Archive.zip", "archivebox.fill"),
            ("Theme.mp3", "waveform"),
            ("Demo.mov", "film.fill"),
            ("Notes.txt", "doc.text.fill"),
            ("Unknown.crest", "doc.fill"),
        ]

        for (filename, expectedSymbol) in expectations {
            XCTAssertEqual(
                BrowserDownloadFileIconPolicy.systemImage(for: filename),
                expectedSymbol
            )
        }
    }

    func testFinishedDownloadRowRevealsTheFileInFinder() {
        XCTAssertEqual(
            BrowserUtilityDownloadPrimaryActionPolicy.destination(
                for: .finished,
                availableDestinations: [.open, .revealInFinder]
            ),
            .revealInFinder
        )
        XCTAssertNil(
            BrowserUtilityDownloadPrimaryActionPolicy.destination(
                for: .downloading,
                availableDestinations: [.open, .revealInFinder]
            )
        )
    }

    func testArchiveFiltersIncludeEveryRemovalCauseWithASymbol() {
        XCTAssertEqual(
            BrowserUtilityListFilter.options(for: .archive),
            [
                .all,
                .archivedClosed,
                .archivedAutomatically,
                .archivedSynced,
                .archivedQuickWindow,
            ]
        )
        for filter in BrowserUtilityListFilter.options(for: .archive) {
            XCTAssertFalse(filter.systemImage.isEmpty)
        }
    }

    func testArchivePreparationSortsByTheTimeTheTabWasClosed() throws {
        let now = Date(timeIntervalSinceReferenceDate: 900)
        let older = ArchivedTab(
            tab: BrowserTab(
                id: TabID(rawValue: identifier(0x73)),
                title: "Older",
                url: URL(string: "https://example.com/older"),
                symbol: "globe",
                placement: .current,
                lastActivatedAt: Date(timeIntervalSinceReferenceDate: 800)
            ),
            archivedAt: Date(timeIntervalSinceReferenceDate: 850),
            reason: .closed
        )
        let newer = ArchivedTab(
            tab: BrowserTab(
                id: TabID(rawValue: identifier(0x74)),
                title: "Newer",
                url: URL(string: "https://example.com/newer"),
                symbol: "globe",
                placement: .current,
                lastActivatedAt: Date(timeIntervalSinceReferenceDate: 100)
            ),
            archivedAt: now,
            reason: .autoCleanup
        )
        let request = BrowserUtilityListRequest(
            surface: .archive,
            assignment: utilityDownloadContext().assignment,
            archivedTabs: [older, newer],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )

        let sections = BrowserUtilityListPreparation.sections(
            for: request,
            now: now,
            calendar: .current
        )

        XCTAssertEqual(
            sections.flatMap(\.items).compactMap { item -> TabID? in
                guard case .archive(let archived) = item else { return nil }
                return archived.id
            },
            [newer.id, older.id]
        )
    }

    @MainActor
    func testOnlyBlankSidebarAndWebContentInteractionsDismissCommonLists() {
        let presentation = BrowserUtilityPresentationState()
        presentation.present(.archive)

        presentation.handleInteraction(.control)
        XCTAssertTrue(presentation.isSwitcherExpanded)

        presentation.handleInteraction(.sidebarBlankSpace)
        XCTAssertFalse(presentation.isSwitcherExpanded)

        presentation.present(.archive)
        presentation.handleInteraction(.webContent)
        XCTAssertFalse(presentation.isSwitcherExpanded)
    }

    @MainActor
    func testCommonListTriggerRetainsItsLiveGlobalFrameForTheFanOrigin() {
        let presentation = BrowserUtilityPresentationState()
        let frame = CGRect(x: 24, y: 612, width: 32, height: 32)

        presentation.recordTriggerFrame(frame)

        XCTAssertEqual(presentation.triggerFrameInGlobal, frame)
    }

    private func localized(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
    }

    private func utilityDownloadContext() -> (
        assignment: BrowserSpaceRuntimeAssignment,
        itemID: UUID,
        section: (BrowserDownloadItem) -> BrowserUtilityListSection
    ) {
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(rawValue: identifier(0x61)),
            profileID: identifier(0x62)
        )
        let now = Date(timeIntervalSinceReferenceDate: 807_969_600)
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = timeZone
        }
        let timeframe = BrowserUtilityTimeSection(
            date: now,
            now: now,
            calendar: calendar
        )
        return (
            assignment,
            identifier(0x63),
            { item in
                BrowserUtilityListSection(
                    timeframe: timeframe,
                    items: [.download(item)]
                )
            }
        )
    }

    private func utilityDownload(
        id: UUID,
        profileID: UUID,
        progress: Double,
        state: BrowserDownloadItemState
    ) -> BrowserDownloadItem {
        BrowserDownloadItem(
            id: id,
            profileID: profileID,
            createdAt: Date(timeIntervalSinceReferenceDate: 807_969_600),
            filename: "Crest.dmg",
            destinationURL: URL(filePath: "/crest-preview/Crest.dmg"),
            progress: progress,
            state: state,
            riskAssessment: nil
        )
    }

    private func identifier(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, finalByte
            )
        )
    }
}
