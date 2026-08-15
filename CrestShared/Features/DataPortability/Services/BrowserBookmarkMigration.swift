import Foundation

enum BrowserBookmarkMigration {
    static let maximumEncodedByteCount = BrowserPortableArchive.maximumEncodedByteCount
    static let defaultHTMLFilename = "Crest Bookmarks.html"

    static func decode(
        _ data: Data,
        source: BrowserBookmarkMigrationSource,
        importedAt: Date = .now
    ) throws -> BrowserPortableImport {
        guard data.count <= maximumEncodedByteCount else {
            throw BrowserBookmarkMigrationError.fileTooLarge
        }

        let drafts: [BrowserBookmarkSpaceDraft]
        switch source {
        case .htmlBookmarks:
            drafts = try BrowserNetscapeBookmarkAdapter.decode(
                data,
                source: source,
                fallbackDate: importedAt
            )
        case .safariBookmarks:
            drafts = [try BrowserBookmarkSourceAdapters.decodeSafari(
                data,
                source: source,
                fallbackDate: importedAt
            )]
        case .chromeBookmarks:
            drafts = [try BrowserBookmarkSourceAdapters.decodeChrome(
                data,
                source: source,
                fallbackDate: importedAt
            )]
        case .firefoxBookmarks:
            drafts = [try BrowserBookmarkSourceAdapters.decodeFirefox(
                data,
                source: source,
                fallbackDate: importedAt
            )]
        case .arcSidebar:
            drafts = try BrowserBookmarkSourceAdapters.decodeArc(
                data,
                source: source,
                fallbackDate: importedAt
            )
        }

        return try materialize(drafts, source: source, importedAt: importedAt)
    }

    static func encodeHTML(
        session: BrowserSession,
        exportedAt: Date = .now
    ) throws -> Data {
        let data = try BrowserNetscapeBookmarkAdapter.encode(
            session: session,
            exportedAt: exportedAt
        )
        guard data.count <= maximumEncodedByteCount else {
            throw BrowserBookmarkMigrationError.fileTooLarge
        }
        return data
    }

    private static func materialize(
        _ sourceDrafts: [BrowserBookmarkSpaceDraft],
        source: BrowserBookmarkMigrationSource,
        importedAt: Date
    ) throws -> BrowserPortableImport {
        let drafts = sourceDrafts.filter { !$0.bookmarks.isEmpty }
        guard !drafts.isEmpty else {
            throw BrowserBookmarkMigrationError.noImportableBookmarks
        }
        guard drafts.count <= BrowserPortableArchive.maximumSpaceCount else {
            throw BrowserBookmarkMigrationError.resourceLimitExceeded
        }

        let spaces = try drafts.map { draft in
            try draft.makeTemporarySpace(source: source)
        }
        let temporarySession = BrowserSession(
            spaces: spaces,
            selectedSpaceID: spaces[0].id
        )

        do {
            return try BrowserPortableArchive(
                session: temporarySession,
                exportedAt: importedAt
            ).materialize()
        } catch let error as BrowserPortableArchiveError {
            switch error {
            case .archiveTooLarge, .spaceLimitExceeded:
                throw BrowserBookmarkMigrationError.resourceLimitExceeded
            case .invalidContents, .missingFileContents, .unrecognizedFormat,
                    .unsupportedSchemaVersion:
                throw BrowserBookmarkMigrationError.invalidContents
            }
        }
    }
}
