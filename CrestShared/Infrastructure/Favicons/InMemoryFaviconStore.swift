import Dispatch
import Foundation

/// Keeps favicons for the run only. What a preview, a test, and a process without
/// an Application Support directory use.
final class InMemoryBrowserFaviconStore: BrowserFaviconStoring, @unchecked Sendable {
    private let accessQueue = DispatchQueue(
        label: "com.pauldavis.crest.favicon-store.memory"
    )
    private var favicons: [UUID: Data] = [:]
    private var savedFavicons: [UUID: BrowserSavedFavicon] = [:]

    func favicon(tabID: UUID) -> Data? {
        accessQueue.sync { favicons[tabID] }
    }

    func reconcile(_ faviconData: Data?, tabID: UUID) {
        accessQueue.sync {
            guard let faviconData, !faviconData.isEmpty else { return }
            favicons[tabID] = faviconData
        }
    }

    func forgetFavicon(tabID: UUID) {
        accessQueue.sync { favicons[tabID] = nil }
    }

    func savedFavicon(tabID: UUID) -> BrowserSavedFavicon? {
        accessQueue.sync { savedFavicons[tabID] }
    }

    func keepSavedFavicon(_ favicon: BrowserSavedFavicon?, tabID: UUID) {
        accessQueue.sync { savedFavicons[tabID] = favicon }
    }

    func pruneFavicons(keeping tabIDs: Set<UUID>) {
        accessQueue.sync {
            favicons = favicons.filter { tabIDs.contains($0.key) }
            savedFavicons = savedFavicons.filter { tabIDs.contains($0.key) }
        }
    }
}
