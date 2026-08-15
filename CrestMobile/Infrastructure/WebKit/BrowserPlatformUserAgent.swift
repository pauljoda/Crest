enum BrowserPlatformUserAgent {
    static func applicationName(
        operatingSystemMajorVersion: Int
    ) -> String {
        "Version/\(operatingSystemMajorVersion).0 Safari/604.1"
    }
}
