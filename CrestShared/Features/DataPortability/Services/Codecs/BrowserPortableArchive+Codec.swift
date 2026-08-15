import Foundation

extension BrowserPortableArchive {
    static func encode(
        session: BrowserSession,
        exportedAt: Date = .now
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(
            BrowserPortableArchive(session: session, exportedAt: exportedAt)
        )
        guard data.count <= maximumEncodedByteCount else {
            throw BrowserPortableArchiveError.archiveTooLarge
        }
        return data
    }

    static func decode(_ data: Data) throws -> BrowserPortableArchive {
        guard data.count <= maximumEncodedByteCount else {
            throw BrowserPortableArchiveError.archiveTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(BrowserPortableArchive.self, from: data)
        } catch let error as BrowserPortableArchiveError {
            throw error
        } catch {
            throw BrowserPortableArchiveError.invalidContents
        }
    }
}
