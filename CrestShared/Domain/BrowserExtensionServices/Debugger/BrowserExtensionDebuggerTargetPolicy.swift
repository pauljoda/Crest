import Foundation

/// Which pages a `chrome.debugger` attachment may ever reach.
///
/// Attaching is strictly more powerful than injecting a content script: the
/// session evaluates arbitrary expressions in the page's own world and reads
/// back object graphs. Host permissions decide whether a *site* is in scope;
/// this policy decides whether a URL is a site at all. Crest surfaces — the
/// Start Page, an install handoff — and other extensions' documents are never
/// in scope, no matter how broad the manifest's host access is.
///
/// This is deliberately not Crest's navigation scheme policy. That one answers
/// "who loads this URL"; this one answers "may a third party drive the page
/// that already did".
enum BrowserExtensionDebuggerTargetPolicy {
    /// The DevTools protocol versions an attachment may ask for.
    ///
    /// Chrome answers this from the protocol build it ships. Crest implements
    /// a subset of the 1.3 surface and reports the same acceptance window, so
    /// a package pinned to any of these attaches and then discovers exactly
    /// which methods exist by calling them.
    static let supportedProtocolVersions: Set<String> = ["1.0", "1.1", "1.2", "1.3"]

    /// Schemes no extension may drive, whatever host access it holds.
    ///
    /// `file` stays out because Chrome gates it behind an explicit local-file
    /// grant Crest does not model, and a debugger session on a `file:` page
    /// reads the local disk through the page. `about:` covers WebKit's own
    /// blank and error documents.
    /// The install-handoff scheme is spelled out rather than read from
    /// `BrowserExtensionInstallScheme`: Domain owns no Infrastructure type.
    static let restrictedSchemes: Set<String> = [
        "about",
        "crest-extension-install",
        "file",
        "javascript",
    ]

    /// Extension document schemes. A package may drive its own documents and
    /// never another package's.
    static let extensionSchemes: Set<String> = [
        "chrome-extension",
        "crest-extension",
        "safari-web-extension",
        "webkit-extension",
    ]

    /// Hosts that install and manage extensions. A package that could drive
    /// them could install, review, or remove packages as the user.
    static let restrictedHosts: Set<String> = [
        "addons.mozilla.org",
        "chrome.google.com",
        "chromewebstore.google.com",
    ]

    /// Whether `url` may be attached to by the package rooted at
    /// `extensionBaseURL`.
    ///
    /// A `nil` URL is Crest's Start Page: a native surface with no document to
    /// debug and no host to match, so it is never a target.
    static func allowsAttachment(to url: URL?, extensionBaseURL: URL) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        guard !restrictedSchemes.contains(scheme) else { return false }
        if extensionSchemes.contains(scheme) {
            return sameOrigin(url, extensionBaseURL)
        }
        guard let host = url.host()?.lowercased() else { return true }
        return !restrictedHosts.contains(host)
    }

    private static func sameOrigin(_ url: URL, _ other: URL) -> Bool {
        url.scheme?.lowercased() == other.scheme?.lowercased()
            && url.host()?.lowercased() == other.host()?.lowercased()
            && url.port == other.port
    }
}
