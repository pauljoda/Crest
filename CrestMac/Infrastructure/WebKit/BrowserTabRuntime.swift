import AppKit
import Observation
import WebKit

/// All WebKit configurations retained by one tab share an owner. The history
/// links point into the suspended pages, so removing this owner releases the
/// whole tab even after navigation crossed an extension configuration boundary.
@MainActor
final class BrowserTabRuntime {
    weak var store: BrowserPageRuntimeStore?
    var tabID: TabID?
    var presentationWindowID: BrowserWindowID?
    var routingWindowID: BrowserWindowID?
    var snapshotGeneration = 0
    var snapshot: NSImage?
    private var snapshots: [ObjectIdentifier: BrowserBackgroundPageSnapshot] = [:]
    private var observedPages: Set<ObjectIdentifier> = []
    var page: BrowserPage
    private(set) var suspendedPages: [BrowserPage] = []
    var backPage: BrowserPage?
    var forwardPage: BrowserPage?

    var allPages: [BrowserPage] { [page] + suspendedPages }

    init(page: BrowserPage) {
        self.page = page
    }

    func replaceCurrentPage(with replacement: BrowserPage) {
        suspendedPages.removeAll { $0 === replacement }
        if page.extensionBaseURL == nil, replacement.extensionBaseURL != nil {
            backPage = page
            forwardPage = nil
        }
        suspendedPages.append(page)
        page = replacement
        currentPageDidChange()
    }

    func swap(to destination: BrowserPage) -> BrowserPage? {
        guard let index = suspendedPages.firstIndex(where: { $0 === destination }) else { return nil }
        let previous = page
        suspendedPages.remove(at: index)
        suspendedPages.append(previous)
        page = destination
        currentPageDidChange()
        return previous
    }

    private func currentPageDidChange() {
        observeCurrentPage()
        let current = BrowserBackgroundPageSnapshot(page: page)
        // Switching to a retained configuration changes tab metadata without
        // completing a new navigation or recording another visit.
        store?.pageDidChange(self, previous: current, current: current, currentPageChanged: true)
    }

    func observeCurrentPage() {
        let identity = ObjectIdentifier(page)
        guard observedPages.insert(identity).inserted else { return }
        snapshots[identity] = BrowserBackgroundPageSnapshot(page: page)
        track(page)
    }

    private func track(_ observedPage: BrowserPage) {
        withObservationTracking {
            _ = BrowserBackgroundPageSnapshot(page: observedPage)
        } onChange: { [weak self, weak observedPage] in
            Task { @MainActor in
                guard let self, let observedPage else { return }
                let identity = ObjectIdentifier(observedPage)
                let previous = self.snapshots[identity]
                let current = BrowserBackgroundPageSnapshot(page: observedPage)
                self.snapshots[identity] = current
                self.track(observedPage)
                guard self.page === observedPage else { return }
                self.store?.pageDidChange(self, previous: previous, current: current)
            }
        }
    }

    func clearHistory() {
        backPage = nil
        forwardPage = nil
    }

    func prepareForRelease() {
        for page in allPages {
            page.prepareForSpaceDeletion()
        }
        clearHistory()
        suspendedPages.removeAll()
    }
}
