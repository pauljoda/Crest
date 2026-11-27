#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageNavigationStarted {
        @MainActor func present(on engine: ChromiumEngine) {
            guard let page = engine.presentedPage(pageID) else { return }
            page.observer(BrowserPageNavigationStarted())
            page.observer(BrowserPageProgressChanged(progress: 0.08))
        }
    }
#endif
