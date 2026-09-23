import WebKit

@MainActor
final class BrowserContentRuleListProvider: BrowserContentRuleListProviding {
    static let shared: BrowserContentRuleListProvider =
        BrowserLaunchEnvironment.current.requiresIsolation
        ? BrowserContentRuleListProvider(ruleListStore: nil)
        : BrowserContentRuleListProvider()

    private let ruleListStore: WKContentRuleListStore?
    private let compiler: any BrowserContentRuleListCompiling
    private var cachedRuleLists: [WKContentRuleList]?

    init(
        ruleListStore: WKContentRuleListStore? = .default(),
        compiler: any BrowserContentRuleListCompiling =
            BrowserContentRuleListCompilerAdapter()
    ) {
        self.ruleListStore = ruleListStore
        self.compiler = compiler
    }

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        guard let ruleListStore else { return [] }
        if let cachedRuleLists { return cachedRuleLists }
        // The core composes Crest's bundled rules. Without them there is
        // nothing to compile, the same as a launch without a rule store.
        guard let rules = BrowserCorePolicy.balancedContentBlockingRules() else { return [] }

        let ruleLists = try await compiler.compile(
            identifiers: [rules.identifier],
            sources: [rules.source],
            store: ruleListStore
        )
        cachedRuleLists = ruleLists
        return ruleLists
    }
}
