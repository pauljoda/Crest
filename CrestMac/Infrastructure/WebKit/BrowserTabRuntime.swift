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
    private var previousSnapshot: BrowserBackgroundPageSnapshot?
    private var observedPageID: ObjectIdentifier?
    var page: BrowserPage

    var allPages: [BrowserPage] { [page] }

    init(page: BrowserPage) {
        self.page = page
    }

    func observeCurrentPage() {
        let identity = ObjectIdentifier(page)
        guard observedPageID != identity else { return }
        observedPageID = identity
        previousSnapshot = BrowserBackgroundPageSnapshot(page: page)
        track(page)
    }

    private func track(_ observedPage: BrowserPage) {
        withObservationTracking {
            _ = BrowserBackgroundPageSnapshot(page: observedPage)
        } onChange: { [weak self, weak observedPage] in
            Task { @MainActor in
                guard let self, let observedPage, self.page === observedPage,
                    self.observedPageID == ObjectIdentifier(observedPage) else { return }
                let previous = self.previousSnapshot
                let current = BrowserBackgroundPageSnapshot(page: observedPage)
                self.previousSnapshot = current
                self.track(observedPage)
                self.store?.pageDidChange(self, previous: previous, current: current)
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
