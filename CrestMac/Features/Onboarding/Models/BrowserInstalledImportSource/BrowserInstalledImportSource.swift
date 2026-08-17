import AppKit

struct BrowserDetectedImportPayload: Equatable, Sendable {
    let application: BrowserImportApplication
    let profiles: [BrowserDetectedImportProfile]
    var passwordStores: [BrowserDetectedPasswordStore] = []
}

struct BrowserDetectedImportProfile: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let bookmarksURL: URL?
    let sessionURL: URL?
}

struct BrowserInstalledImportSource: Identifiable {
    let application: BrowserImportApplication
    let applicationURL: URL
    let detectedPayload: BrowserDetectedImportPayload
    let icon: NSImage

    var id: BrowserImportApplication { application }

    var hasDetectedData: Bool {
        detectedPayload.profiles.contains {
            $0.bookmarksURL != nil || $0.sessionURL != nil
        }
    }
}
