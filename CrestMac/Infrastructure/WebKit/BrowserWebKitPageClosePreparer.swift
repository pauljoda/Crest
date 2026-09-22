import Foundation

/// Asks each WebKit page's beforeunload handlers in turn, so at most one prompt
/// is on screen and the first page that stays vetoes the whole batch. Approval
/// leaves every page alive for the accepted session change to release.
@MainActor
final class BrowserWebKitPageClosePreparer: BrowserPageClosePreparing {
    func prepareToClose(_ pages: [any BrowserPageEngine], completion: @escaping @MainActor (Bool) -> Void) {
        let webKit = pages.compactMap { $0 as? BrowserWebKitPageEngine }
        guard webKit.count == pages.count else { completion(false); return }
        prepare(webKit[...], completion: completion)
    }

    private func prepare(_ pages: ArraySlice<BrowserWebKitPageEngine>,
                         completion: @escaping @MainActor (Bool) -> Void) {
        guard let page = pages.first else { completion(true); return }
        page.prepareToClose { [weak self] allowed in
            guard allowed, let self else { completion(false); return }
            self.prepare(pages.dropFirst(), completion: completion)
        }
    }
}
