#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageContentPainted {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageContentPainted())
        }
    }
#endif
