import Foundation

/// Forwarders kept only for CrestMobile, which another batch owns. Delete this
/// file once `MobileBrowserPage` asks `live.suggestedFilename(pathExtension:)`
/// directly.
enum BrowserPageExportPolicy {
    static func pdfFilename(title: String?, url: URL?) -> String {
        document(title: title, url: url).suggestedFilename(pathExtension: "pdf")
    }

    static func webArchiveFilename(title: String?, url: URL?, format: BrowserPageArchiveFormat = .webArchive) -> String
    {
        document(title: title, url: url).suggestedFilename(pathExtension: format.pathExtension)
    }

    private static func document(title: String?, url: URL?) -> PageLiveState {
        PageLiveState(
            url: url?.absoluteString, pendingURL: nil, title: title ?? "", isLoading: false, canGoBack: false,
            canGoForward: false, security: PageSecurity.none, failure: nil, media: [], address: nil)
    }
}
