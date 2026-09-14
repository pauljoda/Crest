import WebKit

/// All WebKit configurations retained by one tab share an owner. The history
/// links point into the suspended pages, so removing this owner releases the
/// whole tab even after navigation crossed an extension configuration boundary.
@MainActor
final class BrowserTabRuntime {
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
    }

    func swap(to destination: BrowserPage) -> BrowserPage? {
        guard let index = suspendedPages.firstIndex(where: { $0 === destination }) else { return nil }
        let previous = page
        suspendedPages.remove(at: index)
        suspendedPages.append(previous)
        page = destination
        return previous
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
