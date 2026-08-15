import Foundation

enum BrowserPortableArchiveFileIO {
    static func document(for session: BrowserSession) async throws
        -> BrowserPortableArchiveDocument
    {
        let data = try await Task.detached {
            try BrowserPortableArchive.encode(session: session)
        }.value
        return BrowserPortableArchiveDocument(data: data)
    }

    static func read(from url: URL) async throws -> BrowserPortableImport {
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
            guard values.fileSize ?? 0 <= BrowserPortableArchive.maximumEncodedByteCount else {
                throw BrowserPortableArchiveError.archiveTooLarge
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return try BrowserPortableArchive.decode(data).materialize()
        }.value
    }
}
