import AppKit
import Observation
import WebKit

/// One tab's live WebKit page and native presentation ownership.
@MainActor
final class BrowserTabRuntime {
    weak var store: BrowserPageRuntimeStore?
    var tabID: TabID?
    var presentationWindowID: BrowserWindowID?
    var routingWindowID: BrowserWindowID?
    var snapshotGeneration = 0
    var snapshot: NSImage?
    private var observedPageID: ObjectIdentifier?
    var page: BrowserPage

    var allPages: [BrowserPage] { [page] }

    init(page: BrowserPage) {
        self.page = page
    }

    /// Watches the page the tab holds until its first navigation settles, so
    /// residency can count its idle time.
    func observeCurrentPage() {
        let identity = ObjectIdentifier(page)
        guard observedPageID != identity else { return }
        observedPageID = identity
        track(page)
    }

    private func track(_ observedPage: BrowserPage) {
        guard !observedPage.hasSettledNavigation else {
            store?.pageSettled(self)
            return
        }
        withObservationTracking {
            _ = observedPage.hasSettledNavigation
        } onChange: { [weak self, weak observedPage] in
            Task { @MainActor in
                guard let self, let observedPage, self.page === observedPage,
                    self.observedPageID == ObjectIdentifier(observedPage) else { return }
                self.track(observedPage)
            }
        }
    }

    /// Ends every page the tab holds; see `BrowserPage.release(keepingState:)`.
    func release(keepingState: Bool) {
        for page in allPages {
            page.release(keepingState: keepingState)
        }
    }
}
