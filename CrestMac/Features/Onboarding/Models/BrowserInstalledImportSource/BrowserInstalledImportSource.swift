import AppKit

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
