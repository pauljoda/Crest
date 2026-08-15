import Foundation

struct BrowserDetectedImportPayload: Equatable, Sendable {
    let application: BrowserImportApplication
    let profiles: [BrowserDetectedImportProfile]
    var passwordStores: [BrowserDetectedPasswordStore] = []
}
