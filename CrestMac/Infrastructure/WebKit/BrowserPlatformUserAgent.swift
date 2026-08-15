enum BrowserPlatformUserAgent {
    static func applicationName(
        operatingSystemMajorVersion: Int
    ) -> String {
        "Version/\(operatingSystemMajorVersion).0 Safari/605.1.15"
    }
}
