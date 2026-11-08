import WebKit

@MainActor
protocol BrowserContentRuleListCompiling: AnyObject {
    /// The compiled lists `identifiers` name, in order: each one `store`
    /// already holds, or compiled from the source `source` answers for it.
    func compile(
        identifiers: [String],
        source: (String) throws -> String,
        store: WKContentRuleListStore
    ) async throws -> [WKContentRuleList]
}
