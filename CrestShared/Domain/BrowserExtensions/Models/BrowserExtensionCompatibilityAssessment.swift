struct BrowserExtensionCompatibilityAssessment: Equatable, Sendable {
    let issues: [BrowserExtensionCompatibilityIssue]

    var blockingIssues: [BrowserExtensionCompatibilityIssue] {
        issues.filter(\.isBlocking)
    }

    var canRun: Bool {
        blockingIssues.isEmpty
    }

    static let compatible = BrowserExtensionCompatibilityAssessment(
        issues: []
    )
}
