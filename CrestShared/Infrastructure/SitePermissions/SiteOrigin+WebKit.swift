import WebKit

extension BrowserSiteOrigin {
    @MainActor
    init(_ origin: WKSecurityOrigin) {
        self.init(scheme: origin.protocol, host: origin.host, port: origin.port)
    }
}
