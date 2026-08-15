import Foundation

/// A `chrome.history.search` request.
struct BrowserExtensionHistoryQuery: Equatable, Hashable, Sendable {
    /// Chrome's documented default when an extension omits `maxResults`.
    static let defaultMaximumResults = 100

    /// Free text matched against both the title and the full URL. Empty text
    /// matches everything, which is how `chrome.history.search` asks for the
    /// most recent entries.
    let text: String
    /// Inclusive lower bound on the last visit time.
    let startTime: Date?
    /// Exclusive upper bound on the last visit time, mirroring Chrome.
    let endTime: Date?
    let maximumResults: Int

    init(
        text: String = "",
        startTime: Date? = nil,
        endTime: Date? = nil,
        maximumResults: Int = defaultMaximumResults
    ) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.maximumResults = maximumResults
    }

    /// Whether `date` falls inside this query's window.
    func containsVisit(at date: Date) -> Bool {
        if let startTime, date < startTime { return false }
        if let endTime, date >= endTime { return false }
        return true
    }
}
