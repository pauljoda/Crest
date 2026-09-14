import WebKit

extension BrowserPlatformPage {
    func synchronizePopupPermission(for url: URL? = nil) {
        let origin = (url ?? displayURL ?? webView.url)
            .flatMap(BrowserSiteOrigin.init(url:))
        let decision =
            origin.map {
                permissionCenter.decision(for: .popups, origin: $0, in: spaceID)
            } ?? .ask
        let allowsAutomaticPopups =
            BrowserAutomaticPopupPolicy.allowsAutomaticPopups(decision: decision)
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically =
            allowsAutomaticPopups
        recordPopupPermissionSynchronized(
            allowsAutomaticPopups: allowsAutomaticPopups,
            origin: origin
        )
    }

    func applyContentBlocking(
        policy: BrowserContentBlockingPolicy,
        balancedRuleList: WKContentRuleList?,
        activation: BrowserContentRuleListActivation = .onNextNavigation
    ) {
        applyContentBlocking(
            policy: policy,
            balancedRuleLists: balancedRuleList.map { [$0] } ?? [],
            activation: activation
        )
    }
}
