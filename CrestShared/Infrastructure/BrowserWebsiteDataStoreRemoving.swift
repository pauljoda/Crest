import Foundation
import WebKit

@MainActor
protocol BrowserWebsiteDataStoreRemoving {
    func removePersistentDataStore(for profile: BrowsingProfile) async throws
}
