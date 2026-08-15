import Foundation

struct BrowserDetectedImportProfile: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let bookmarksURL: URL?
    let sessionURL: URL?
}
