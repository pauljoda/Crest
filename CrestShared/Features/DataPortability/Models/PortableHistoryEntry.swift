import Foundation

struct PortableHistoryEntry: Codable, Equatable, Sendable {
    let url: String
    let title: String
    let firstVisitedAt: Date
    let lastVisitedAt: Date
    let visitCount: Int

    init(_ entry: BrowserHistoryEntry) {
        url =
            ArchiveValidation.sanitizedURL(entry.url, removesFragment: true)?
            .absoluteString
            ?? entry.url.absoluteString
        title = entry.title
        firstVisitedAt = entry.firstVisitedAt
        lastVisitedAt = entry.lastVisitedAt
        visitCount = entry.visitCount
    }

    func materialize() throws -> BrowserHistoryEntry {
        try ArchiveValidation.requireText(title, maximumLength: ArchiveLimits.maximumTabTitleLength)
        try ArchiveValidation.requireDate(firstVisitedAt)
        try ArchiveValidation.requireDate(lastVisitedAt)
        guard visitCount > 0,
            visitCount <= ArchiveLimits.maximumVisitCount,
            firstVisitedAt <= lastVisitedAt
        else {
            throw BrowserPortableArchiveError.invalidContents
        }
        guard
            let materializedURL = try ArchiveValidation.materializeURL(
                url,
                removesFragment: true
            )
        else {
            throw BrowserPortableArchiveError.invalidContents
        }
        return BrowserHistoryEntry(
            url: materializedURL,
            title: title,
            firstVisitedAt: firstVisitedAt,
            lastVisitedAt: lastVisitedAt,
            visitCount: visitCount
        )
    }
}
