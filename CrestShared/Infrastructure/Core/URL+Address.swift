import Foundation

extension URL {
    // MARK: - Variables

    /// The web scheme the URL names, in any case, or nil for any other.
    var webScheme: WebScheme? { WebScheme.named(scheme?.lowercased()) }

    /// The scheme Crest decides about that the URL names, in any case, or nil
    /// for one that belongs to another application.
    var urlScheme: UrlScheme? { UrlScheme.named(scheme?.lowercased()) }

    // MARK: - Initializers

    /// The URL an address the core keeps, or an engine reports, spells. A
    /// character a URL cannot hold is escaped where it stands, as the core
    /// escapes it, and every escape the address spells is kept: Foundation's
    /// own parser would escape the whole part it is in, `%` included, and the
    /// page would get a query it never asked for. Nil for no URL at all.
    init?(address: String) {
        if let url = URL(string: address, encodingInvalidCharacters: false) {
            self = url
        } else if let escaped = try? CrestCore.answer(EscapedAddress(spelling: address)) {
            self.init(string: escaped)
        } else {
            self.init(string: address)
        }
    }
}
