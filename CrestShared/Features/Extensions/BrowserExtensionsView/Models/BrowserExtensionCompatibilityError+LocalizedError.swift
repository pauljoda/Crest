import Foundation

extension BrowserExtensionCompatibilityError: LocalizedError {
    var errorDescription: String? {
        assessment.blockingIssues.map(\.message).joined(separator: "\n")
    }
}
