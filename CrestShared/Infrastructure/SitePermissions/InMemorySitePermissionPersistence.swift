import Foundation

final class InMemoryBrowserSitePermissionPersistence: BrowserSitePermissionPersisting {
    private(set) var document: Data?

    init(document: Data? = nil) {
        self.document = document
    }

    /// The saved records, decoded for inspection.
    var records: [BrowserSitePermissionRecord] {
        document.flatMap { try? JSONDecoder().decode([BrowserSitePermissionRecord].self, from: $0) } ?? []
    }

    func loadDocument() -> Data? {
        document
    }

    func saveDocument(_ document: Data) {
        self.document = document
    }
}
