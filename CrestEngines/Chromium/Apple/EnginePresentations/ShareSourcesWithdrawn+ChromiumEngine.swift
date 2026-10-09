#if CREST_CHROMIUM_HOST
    import Foundation

    extension ShareSourcesWithdrawn {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(.shareSourcesWithdrawn(shareID: shareID))
        }
    }
#endif
