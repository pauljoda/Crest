#if CREST_CHROMIUM_HOST
    import Foundation

    extension PagePasswordControlChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(
                BrowserPagePasswordControlChanged(extensionControlsPasswords: extensionControlsPasswords))
        }
    }
#endif
