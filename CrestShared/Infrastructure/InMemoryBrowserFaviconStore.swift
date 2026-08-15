import Dispatch
import Foundation

/// Keeps favicons for the run only. What a preview, a test, and a process without
/// an Application Support directory use.
final class InMemoryBrowserFaviconStore: BrowserFaviconStoring, @unchecked Sendable {
    private let accessQueue = DispatchQueue(
        label: "com.pauldavis.crest.favicon-store.memory"
    )
    private var favicons: [TabID: Data] = [:]

    var storedTabIDs: Set<TabID> {
        accessQueue.sync { Set(favicons.keys) }
    }

    func favicon(tabID: TabID) -> Data? {
        accessQueue.sync { favicons[tabID] }
    }

    func reconcile(_ faviconData: Data?, tabID: TabID) {
        accessQueue.sync {
            guard let faviconData, !faviconData.isEmpty else { return }
            favicons[tabID] = faviconData
        }
    }

    func pruneFavicons(keeping tabIDs: Set<TabID>) {
        accessQueue.sync {
            favicons = favicons.filter { tabIDs.contains($0.key) }
        }
    }
}
