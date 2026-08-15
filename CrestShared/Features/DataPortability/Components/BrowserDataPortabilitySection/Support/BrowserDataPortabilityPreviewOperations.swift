import Foundation

@MainActor
struct BrowserDataPortabilityPreviewOperations:
    BrowserDataPortabilityOperating
{
    func portableArchiveDocument(
        for _: BrowserSession
    ) async throws -> BrowserPortableArchiveDocument {
        BrowserPortableArchiveDocument(data: Data())
    }

    func portableImport(from _: URL) async throws -> BrowserPortableImport {
        Self.emptyImport
    }

    func bookmarkDocument(
        for _: BrowserSession
    ) async throws -> BrowserBookmarkHTMLDocument {
        BrowserBookmarkHTMLDocument(data: Data())
    }

    func bookmarkImport(
        from _: URL,
        source _: BrowserBookmarkMigrationSource
    ) async throws -> BrowserPortableImport {
        Self.emptyImport
    }

    func historyImport(
        from _: URL,
        source _: BrowserHistoryMigrationSource
    ) async throws -> BrowserPortableImport {
        Self.emptyImport
    }

    func tabImport(
        from _: URL,
        source _: BrowserTabMigrationSource
    ) async throws -> BrowserPortableImport {
        Self.emptyImport
    }

    private static let emptyImport = BrowserPortableImport(
        spaces: [],
        summary: BrowserPortableImportSummary(
            spaceCount: 0,
            folderCount: 0,
            liveTabCount: 0,
            archivedTabCount: 0,
            historyEntryCount: 0
        )
    )
}
