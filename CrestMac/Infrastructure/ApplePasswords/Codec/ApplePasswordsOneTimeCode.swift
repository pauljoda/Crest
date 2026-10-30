import Foundation

/// One code the helper lists for a site. The value is only read after the
/// person picks the row, and is never logged.
struct ApplePasswordsOneTimeCode: Equatable, Sendable {
    let source: ApplePasswordsOneTimeCodeSource
    let code: String?
    let username: String?
    let domain: String?

    /// The host the entry names, as a bare host or as a URL, in lower case.
    var domainHost: String? {
        guard let domain = domain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty else {
            return nil
        }
        let spelled = domain.contains("://") ? domain : "https://\(domain)"
        guard let host = URLComponents(string: spelled)?.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    /// Whether the entry may be offered to, and filled into, `frame`.
    ///
    /// The query names the top-level origin beside the frame's, so a frame
    /// that is not the top-level page must not receive the page's codes: there
    /// only an entry whose domain is the frame's own host belongs to it, and
    /// one with no readable domain does not.
    func belongs(toFrame frame: CredentialOrigin, topLevel: CredentialOrigin) -> Bool {
        guard frame != topLevel else { return true }
        return domainHost == frame.host.lowercased()
    }
}
