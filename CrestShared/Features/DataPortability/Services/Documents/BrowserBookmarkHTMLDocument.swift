import SwiftUI
import UniformTypeIdentifiers

struct BrowserBookmarkHTMLDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.html]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BrowserPortableArchiveError.missingFileContents
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
