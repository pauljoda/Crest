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

    var hasReadableDetectedData: Bool {
        let urls =
            detectedPayload.profiles.flatMap { profile in
                [profile.bookmarksURL, profile.sessionURL].compactMap { $0 }
            } + detectedPayload.passwordStores.map(\.databaseURL)
        return !urls.isEmpty
            && urls.allSatisfy {
                FileManager.default.isReadableFile(atPath: $0.path)
            }
    }
}
