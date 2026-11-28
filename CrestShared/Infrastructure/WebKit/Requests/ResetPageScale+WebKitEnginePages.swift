import Foundation

extension ResetPageScale {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        #if os(macOS)
            // A pinch magnifies the view, apart from the page's zoom.
            guard let webView = pages.page(pageID)?.webView, webView.magnification != 1 else { return false }
            webView.magnification = 1
            return true
        #else
            false
        #endif
    }
}
