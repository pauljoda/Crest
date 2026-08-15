import Foundation

/// A scripted keyword provider for tests, previews, and isolated launches.
///
/// It answers with whatever ``suggestions`` currently holds and records every
/// callback the palette made, which is what lets a test assert that keyword
/// routing, acceptance, and deletion reached the right provider with the right
/// arguments.
@MainActor
final class InMemoryBrowserOmniboxProvider: BrowserOmniboxSuggesting {
    let descriptor: BrowserOmniboxDescriptor

    /// Rows returned for the next query.
    var suggestions: [BrowserOmniboxSuggestion]

    private(set) var requestedQueries: [String] = []
    private(set) var acceptedContents: [String] = []
    private(set) var acceptedDispositions: [BrowserOmniboxDisposition] = []
    private(set) var deletedContents: [String] = []
    private(set) var inputStartedCount = 0
    private(set) var inputCancelledCount = 0

    init(
        descriptor: BrowserOmniboxDescriptor,
        suggestions: [BrowserOmniboxSuggestion] = []
    ) {
        self.descriptor = descriptor
        self.suggestions = suggestions
    }

    func suggestions(for query: String) async -> [BrowserOmniboxSuggestion] {
        requestedQueries.append(query)
        return suggestions
    }

    func inputStarted() {
        inputStartedCount += 1
    }

    func inputCancelled() {
        inputCancelledCount += 1
    }

    func accept(_ content: String, disposition: BrowserOmniboxDisposition) {
        acceptedContents.append(content)
        acceptedDispositions.append(disposition)
    }

    func deleteSuggestion(_ content: String) {
        deletedContents.append(content)
        suggestions.removeAll { $0.content == content }
    }
}
