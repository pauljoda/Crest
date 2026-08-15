import WebKit

@MainActor
final class BrowserContentRuleListProvider: BrowserContentRuleListProviding {
    static let shared: BrowserContentRuleListProvider =
        BrowserLaunchIsolationPolicy.requiresIsolation(.current)
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

        let ruleLists = try await compiler.compile(
            identifiers: [BrowserContentBlockingRules.identifier],
            sources: [BrowserContentBlockingRules.balancedSource],
            store: ruleListStore
        )
        cachedRuleLists = ruleLists
        return ruleLists
    }
}
