import Observation
import WebKit

/// Owns only Crest's rules on a controller that may also carry extension rules.
/// The page's Space decides whether it blocks, and the site it shows may have
/// blocking turned off: `blocksSite` asks the core about a site, and a main-frame
/// navigation to another site swaps the rules before the page loads it.
@Observable
@MainActor
final class BrowserPageContentRuleSession {
    private(set) var isActive: Bool
    @ObservationIgnored private(set) var ruleLists: [WKContentRuleList]
    /// Whether the page's Space blocks at a URL's site.
    @ObservationIgnored private let blocksSite: @MainActor (URL?) -> Bool
    /// What the page's Space last applied, which a navigation re-applies for
    /// the site it goes to.
    @ObservationIgnored private var policy: ContentBlockingPolicy?
    @ObservationIgnored private var balancedRuleLists: [WKContentRuleList] = []

    init(
        ruleLists: [WKContentRuleList],
        additionalRuleList: WKContentRuleList?,
        blocksSite: @escaping @MainActor (URL?) -> Bool = { _ in true }
    ) {
        var installed = ruleLists
        if let additionalRuleList, !installed.contains(where: { $0 === additionalRuleList }) {
            installed.append(additionalRuleList)
        }
        self.ruleLists = installed
        self.blocksSite = blocksSite
        isActive = !installed.isEmpty
    }

    /// A list refresh takes effect on the next navigation unless the user
    /// explicitly changed protection for this page. Never discard a form just
    /// because the filter lists were updated. A page that already loaded
    /// before it had any protection, such as one opened while the rules
    /// compiled at launch, reloads once with its first rules.
    func apply(
        policy: ContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList],
        to webView: WKWebView,
        reloadsImmediately: Bool
    ) {
        let loadedUnprotected = self.policy == nil && ruleLists.isEmpty && webView.url != nil
        self.policy = policy
        self.balancedRuleLists = balancedRuleLists
        install(for: webView.url, in: webView, reloadsImmediately: reloadsImmediately || loadedUnprotected)
    }

    /// Gives a main-frame navigation to `url` the rules of its site before the
    /// page loads it.
    func navigating(to url: URL, in webView: WKWebView) {
        guard policy != nil else { return }
        install(for: url, in: webView, reloadsImmediately: false)
    }

    private func install(for url: URL?, in webView: WKWebView, reloadsImmediately: Bool) {
        let blocks = policy?.blocksContent == true && blocksSite(url)
        let desired = blocks ? balancedRuleLists : []
        guard
            ruleLists.count != desired.count
                || !zip(ruleLists, desired).allSatisfy({ $0 === $1 })
        else { return }

        let controller = webView.configuration.userContentController
        for ruleList in ruleLists {
            controller.remove(ruleList)
        }
        for ruleList in desired {
            controller.add(ruleList)
        }
        ruleLists = desired
        isActive = !desired.isEmpty
        if reloadsImmediately { webView.reload() }
    }
}
