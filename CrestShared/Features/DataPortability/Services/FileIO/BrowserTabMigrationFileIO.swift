import Foundation

enum BrowserTabMigrationFileIO {
    static func read(
        from url: URL,
        source: BrowserTabMigrationSource
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
                throw BrowserTabMigrationError.invalidContents
            }
            guard values.fileSize ?? 0 <= BrowserTabMigration.maximumEncodedByteCount else {
                throw BrowserTabMigrationError.fileTooLarge
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return try BrowserTabMigration.decode(data, source: source)
        }.value
    }
}
