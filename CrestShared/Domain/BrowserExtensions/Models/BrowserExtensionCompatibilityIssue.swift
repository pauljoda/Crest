struct BrowserExtensionCompatibilityIssue: Equatable, Sendable {
    let kind: BrowserExtensionCompatibilityIssueKind
    let isBlocking: Bool
}
