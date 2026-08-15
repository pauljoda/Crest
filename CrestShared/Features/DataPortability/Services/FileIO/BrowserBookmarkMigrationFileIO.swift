import Foundation

enum BrowserBookmarkMigrationFileIO {
    static func document(for session: BrowserSession) async throws
        -> BrowserBookmarkHTMLDocument
    {
        let data = try await Task.detached {
            try BrowserBookmarkMigration.encodeHTML(session: session)
        }.value
        return BrowserBookmarkHTMLDocument(data: data)
    }

    static func read(
        from url: URL,
        source: BrowserBookmarkMigrationSource
    ) async throws -> BrowserPortableImport {
        try await Task.detached {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                throw BrowserPortableArchiveError.missingFileContents
            }
            guard values.fileSize ?? 0 <= BrowserBookmarkMigration.maximumEncodedByteCount else {
                throw BrowserBookmarkMigrationError.fileTooLarge
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return try BrowserBookmarkMigration.decode(data, source: source)
        }.value
    }
}
