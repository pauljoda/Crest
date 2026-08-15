import Foundation

@MainActor
struct LiveBrowserDataPortabilityOperations: BrowserDataPortabilityOperating {
    func portableArchiveDocument(
        for session: BrowserSession
    ) async throws -> BrowserPortableArchiveDocument {
        try await BrowserPortableArchiveFileIO.document(for: session)
    }

    func portableImport(from url: URL) async throws -> BrowserPortableImport {
        try await BrowserPortableArchiveFileIO.read(from: url)
    }

    func bookmarkDocument(
        for session: BrowserSession
    ) async throws -> BrowserBookmarkHTMLDocument {
        try await BrowserBookmarkMigrationFileIO.document(for: session)
    }

    func bookmarkImport(
        from url: URL,
        source: BrowserBookmarkMigrationSource
    ) async throws -> BrowserPortableImport {
        try await BrowserBookmarkMigrationFileIO.read(from: url, source: source)
    }

    func historyImport(
        from url: URL,
        source: BrowserHistoryMigrationSource
    ) async throws -> BrowserPortableImport {
        try await BrowserHistoryMigration.read(from: url, source: source)
    }

    func tabImport(
        from url: URL,
        source: BrowserTabMigrationSource
    ) async throws -> BrowserPortableImport {
        try await BrowserTabMigrationFileIO.read(from: url, source: source)
    }
}
