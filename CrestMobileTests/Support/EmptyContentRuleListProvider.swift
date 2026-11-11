import WebKit

@testable import CrestMobile

/// Content blocking with no rules, so a test prepares a window's pages
/// without compiling the real lists.
@MainActor
final class EmptyContentRuleListProvider: BrowserContentRuleListProviding {
    func balancedRuleLists() async throws -> [WKContentRuleList] { [] }
}
