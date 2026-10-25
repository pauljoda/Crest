import WebKit

@MainActor
protocol BrowserContentRuleListProviding: AnyObject {
    func balancedRuleLists() async throws -> [WKContentRuleList]
    func refreshedRuleLists() async throws -> [WKContentRuleList]
}
