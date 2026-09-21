import Foundation

enum BrowserExternalURLPolicy {
    static func accepts(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return url.host(percentEncoded: false)?.isEmpty == false
    }

    /// A local document handed over as a document open — Finder double-click, Open
    /// With, or `open -a Crest file.html` — rather than as a web link.
    ///
    /// Kept apart from `accepts` on purpose. Every other caller of this policy is
    /// deciding what a *web* link may do: a peek, a drop, a popup, a download
    /// destination, a context-menu item. Letting `file://` through there would let
    /// a page or another app steer Crest at arbitrary local paths, so the answer
    /// there stays no, and only the document-open route asks this question.
    static func acceptsLocalDocument(_ url: URL) -> Bool {
        BrowserLocalFilePolicy.accepts(url)
    }
}
