import WebKit

@MainActor
final class BrowserContentRuleListCompilerAdapter: BrowserContentRuleListCompiling {
    func compile(
        identifiers: [String],
        source: (String) throws -> String,
        store: WKContentRuleListStore
    ) async throws -> [WKContentRuleList] {
        var lists: [WKContentRuleList] = []
        for identifier in identifiers {
            if let existing = try? await BrowserContentRuleListCompiler.lookUp(
                identifier: identifier,
                store: store
            ) {
                lists.append(existing)
            } else {
                lists.append(
                    try await BrowserContentRuleListCompiler.compile(
                        identifier: identifier,
                        source: try source(identifier),
                        store: store
                    )
                )
            }
        }
        return lists
    }
}
