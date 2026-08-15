import Foundation

struct BrowserDetectedPasswordStore: Equatable, Identifiable, Sendable {
    let id: String
    let profileName: String
    let databaseURL: URL
}
