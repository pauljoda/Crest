#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageLoadProgressed {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageProgressChanged(progress: progress))
        }
    }
#endif
