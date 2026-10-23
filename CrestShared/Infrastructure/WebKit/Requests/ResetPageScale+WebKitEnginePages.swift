import Foundation

extension ResetPageScale {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        #if os(macOS)
            pages.page(pageID).map { $0.webView.magnification = 1 } != nil
        #else
            pages.page(pageID) != nil
        #endif
    }
}
