import Foundation

/// One parsed `<updatecheck>` answer from Google's Omaha endpoint.
///
/// Only the fields Crest acts on are kept. In particular the response's
/// `codebase` download URL is deliberately **not** modelled: Crest downloads
/// replacements through its own pinned redirect endpoint and CRX3 verifier,
/// so an attacker who could rewrite this document still cannot point Crest at
/// a package of their choosing.
struct BrowserChromeWebStoreUpdateCheck: Equatable, Sendable {
    let extensionID: BrowserChromeExtensionID

    /// The version the store currently publishes, or `nil` when the store
    /// answered `noupdate` for the version Crest reported.
    let publishedVersion: String?
}
