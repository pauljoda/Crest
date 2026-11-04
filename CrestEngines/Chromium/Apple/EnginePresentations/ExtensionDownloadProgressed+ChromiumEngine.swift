#if CREST_CHROMIUM_HOST
    import Foundation

    extension ExtensionDownloadProgressed {
        @MainActor func present(on engine: ChromiumEngine) {
            ChromiumComposition.extensions.downloadProgressed(installID, fraction: fraction)
        }
    }
#endif
