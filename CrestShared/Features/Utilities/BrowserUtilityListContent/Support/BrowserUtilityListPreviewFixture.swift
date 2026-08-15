import Foundation

enum BrowserUtilityListPreviewFixture {
    static let referenceDate = Date(timeIntervalSinceReferenceDate: 807_969_600)
    static let assignment = BrowserSpaceRuntimeAssignment(
        spaceID: SpaceID(rawValue: identifier(0x21)),
        profileID: identifier(0x11)
    )

    static let historyEntry = BrowserHistoryEntry(
        id: identifier(0x31),
        url: previewURL("history"),
        title: "Crest Project Notes",
        firstVisitedAt: referenceDate.addingTimeInterval(-3_600),
        lastVisitedAt: referenceDate,
        visitCount: 3
    )

    static let archivedTab = ArchivedTab(
        tab: BrowserTab(
            id: TabID(rawValue: identifier(0x41)),
            title: "Architecture Notes",
            url: previewURL("archive"),
            symbol: "doc.text.fill",
            faviconData: inlineFaviconData,
            iconMode: .pulled,
            placement: .saved,
            lastActivatedAt: referenceDate.addingTimeInterval(-7_200)
        ),
        archivedAt: referenceDate.addingTimeInterval(-1_800),
        reason: .closed
    )

    static let historySpace = BrowserSpace(
        id: assignment.spaceID,
        profile: BrowsingProfile(id: assignment.profileID),
        name: "Research",
        symbol: "books.vertical.fill",
        accent: .indigo,
        folders: [],
        tabs: [
            BrowserTab(
                id: TabID(rawValue: identifier(0x42)),
                title: "Current Notes",
                url: previewURL("current"),
                symbol: "doc.text",
                faviconData: inlineFaviconData,
                iconMode: .pulled,
                placement: .current,
                lastActivatedAt: referenceDate
            )
        ],
        archivedTabs: [archivedTab],
        history: [historyEntry],
        selectedTabID: TabID(rawValue: identifier(0x42))
    )

    static let preparingDownload = download(
        id: identifier(0x51),
        filename: "Crest.dmg",
        state: .preparing
    )

    static let activeDownload = download(
        id: identifier(0x52),
        filename: "Crest.dmg",
        progress: 0.64,
        state: .downloading
    )

    static let finishedDownload = download(
        id: identifier(0x53),
        filename: "Crest.dmg",
        progress: 1,
        state: .finished
    )

    static let failedDownload = download(
        id: identifier(0x54),
        filename: "Crest.dmg",
        state: .failed("The connection was interrupted.")
    )

    static let historyRequest = BrowserUtilityListRequest(
        surface: .history,
        assignment: assignment,
        archivedTabs: [],
        history: [historyEntry],
        downloads: [],
        searchText: "",
        filter: .all
    )

    static let historySection = BrowserUtilityListSection(
        timeframe: BrowserUtilityTimeSection(
            date: referenceDate,
            now: referenceDate,
            calendar: fixedCalendar
        ),
        items: [.history(historyEntry)]
    )

    static let downloadSection = BrowserUtilityListSection(
        timeframe: BrowserUtilityTimeSection(
            date: referenceDate,
            now: referenceDate,
            calendar: fixedCalendar
        ),
        items: [.download(activeDownload), .download(failedDownload)]
    )

    static var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    private static func download(
        id: UUID,
        filename: String,
        progress: Double = 0,
        state: BrowserDownloadItemState
    ) -> BrowserDownloadItem {
        BrowserDownloadItem(
            id: id,
            profileID: assignment.profileID,
            createdAt: referenceDate,
            filename: filename,
            destinationURL: URL(filePath: "/crest-preview/\(filename)"),
            progress: progress,
            state: state,
            riskAssessment: nil
        )
    }

    private static func identifier(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, finalByte
            )
        )
    }

    private static func previewURL(_ path: String) -> URL {
        guard let url = URL(string: "crest-preview://utility/\(path)") else {
            preconditionFailure("Browser Utility preview URL is invalid")
        }
        return url
    }

    private static let inlineFaviconData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0x60, 0x68, 0xF8, 0xCF,
        0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89,
        0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ])
}
