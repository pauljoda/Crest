import Foundation

/// Forwarders kept only for call sites another batch owns (CrestMobile and
/// transient browsing). Each answer now lives on its core query type; delete
/// this file once those call sites ask `ExternalWebLink.accepts(_:)` and
/// `AuthenticationSource.label(host:port:scheme:emptyHostLabel:)` directly.
enum BrowserCorePolicy {
    static func acceptsExternalURL(_ url: URL) -> Bool {
        ExternalWebLink.accepts(url)
    }

    static func authenticationSourceLabel(host: String, port: Int, scheme: String?, emptyHostLabel: String) -> String {
        AuthenticationSource.label(host: host, port: port, scheme: scheme, emptyHostLabel: emptyHostLabel)
    }
}
