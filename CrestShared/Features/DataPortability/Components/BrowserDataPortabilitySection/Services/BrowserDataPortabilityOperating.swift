import Foundation

@MainActor
protocol BrowserDataPortabilityOperating {
    func portableArchiveDocument(
        for session: BrowserSession
    ) async throws -> BrowserPortableArchiveDocument

    func portableImport(from url: URL) async throws -> BrowserPortableImport

    func bookmarkDocument(
        for session: BrowserSession
    ) async throws -> BrowserBookmarkHTMLDocument

    func bookmarkImport(
        from url: URL,
        source: BrowserBookmarkMigrationSource
    ) async throws -> BrowserPortableImport

    func historyImport(
        from url: URL,
        source: BrowserHistoryMigrationSource
    ) async throws -> BrowserPortableImport

    func tabImport(
        from url: URL,
        source: BrowserTabMigrationSource
    ) async throws -> BrowserPortableImport
}
