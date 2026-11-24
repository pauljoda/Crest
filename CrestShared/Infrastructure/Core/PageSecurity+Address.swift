import Foundation

extension PageSecurity {
    // MARK: - Actions - Address

    /// Whether an address field shows its padlock: the security the core
    /// judged for the page a tab shows, or, while the tab has no page, whether
    /// the tab's stored address uses a secure scheme.
    static func isSecure(page: PageLiveState?, storedAddress: String? = nil) -> Bool {
        if let page { return page.security.isSecure }
        let scheme = storedAddress.flatMap(URL.init(string:))?.scheme?.lowercased()
        return WebScheme.named(scheme)?.isSecure == true
    }
}
