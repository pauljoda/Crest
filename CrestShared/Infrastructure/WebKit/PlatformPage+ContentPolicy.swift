import WebKit

extension BrowserPlatformPage {
    func synchronizePopupPermission(for url: URL? = nil) {
        let origin = (url ?? displayURL ?? webKitView?.url)
            .flatMap(BrowserSiteOrigin.init(url:))
        let decision =
            origin.map {
                permissionCenter.decision(for: .popups, origin: $0, in: spaceID)
            } ?? .ask
        let allowsAutomaticPopups =
            BrowserCorePolicy.allowsAutomaticPopups(decision: decision)
        // Crest's decision is the record; an engine with its own blocker is
        // told it, and WebKit reads it from its preferences.
        if !pageEngine.applyAutomaticPopups(allowsAutomaticPopups) {
            guard let webView = webKitView else { return }
            webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically =
                allowsAutomaticPopups
        }
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
