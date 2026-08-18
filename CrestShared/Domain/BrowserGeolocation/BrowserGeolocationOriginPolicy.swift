enum BrowserGeolocationOriginPolicy {
    static func allows(_ origin: BrowserSiteOrigin) -> Bool {
        if origin.scheme == "https" { return true }
        guard origin.scheme == "http" else { return false }
        return origin.host == "localhost"
            || origin.host == "127.0.0.1"
            || origin.host == "::1"
    }
}
