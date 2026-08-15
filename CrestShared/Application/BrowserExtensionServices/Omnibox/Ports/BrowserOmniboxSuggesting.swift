import Foundation

/// A source of keyword-scoped address-bar suggestions.
///
/// Backs `chrome.omnibox`. Each method corresponds to one of the namespace's
/// events, and only ``suggestions(for:)`` must be implemented — the rest carry
/// no-op defaults, because most providers care about acceptance alone.
@MainActor
protocol BrowserOmniboxSuggesting: AnyObject {
    /// How this provider announces itself and what its keyword is.
    var descriptor: BrowserOmniboxDescriptor { get }

    /// Rows for the text following the keyword. Backs `onInputChanged`.
    ///
    /// Called on every keystroke and cancelled when the person keeps typing, so
    /// implementations should honor cancellation rather than race each other.
    func suggestions(for query: String) async -> [BrowserOmniboxSuggestion]

    /// The person entered keyword mode. Backs `onInputStarted`.
    func inputStarted()

    /// The person left keyword mode without picking anything. Backs
    /// `onInputCancelled`.
    func inputCancelled()

    /// The person picked a row. Backs `onInputEntered`.
    func accept(_ content: String, disposition: BrowserOmniboxDisposition)

    /// The person removed a deletable row. Backs `onDeleteSuggestion`.
    func deleteSuggestion(_ content: String)
}
