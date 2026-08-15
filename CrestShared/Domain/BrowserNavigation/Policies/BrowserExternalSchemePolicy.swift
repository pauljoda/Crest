import Foundation

enum BrowserExternalSchemePolicy {
    /// Schemes WebKit itself must keep. `data:` is here rather than in
    /// `blockedSchemes` because WebKit, not Crest, enforces the rule that a
    /// top-level `data:` navigation from web content is refused: routing one to
    /// another app instead would walk around that refusal, and a nested `data:`
    /// payload would arrive somewhere that never asked for it.
    static let webKitOwnedSchemes: Set<String> = [
        "http",
        "https",
        "about",
        "blob",
        "data",
        "webkit-extension",
    ]

    /// Schemes that may never load and may never reach another application.
    /// WebKit evaluates a `javascript:` href before it consults the policy
    /// delegate, so this is defence in depth rather than a change to how
    /// ordinary `javascript:` links behave.
    static let blockedSchemes: Set<String> = ["javascript"]

    /// `file:` sits between the two lists. Crest may open a local document it
    /// chose itself — developer mode already turns on for one — but web content
    /// asking for a file URL is asking to read the user's disk, so only an
    /// app-initiated load keeps it.
    static func disposition(
        for url: URL?,
        isAppInitiated: Bool = false
    ) -> BrowserExternalSchemeDisposition {
        guard let scheme = url?.scheme?.lowercased(), !scheme.isEmpty else {
            // A request WebKit built without a scheme is WebKit's to resolve,
            // exactly as it was before Crest classified schemes at all.
            return .webKit
        }
        if webKitOwnedSchemes.contains(scheme) {
            return .webKit
        }
        if blockedSchemes.contains(scheme) {
            return .blocked
        }
        if scheme == "file" {
            return isAppInitiated ? .webKit : .blocked
        }
        return .handOff
    }
}
