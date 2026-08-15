extension BrowserExtensionDiscoverySource {
    var title: String {
        switch self {
        case .safariApplication:
            "Safari App"
        }
    }

    var detail: String {
        switch self {
        case .safariApplication(let name):
            name
        }
    }

    var symbol: String {
        switch self {
        case .safariApplication:
            "safari"
        }
    }
}
