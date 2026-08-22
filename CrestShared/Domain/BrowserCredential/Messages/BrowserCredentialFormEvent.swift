import Foundation

enum BrowserCredentialFormEvent: String, Equatable, Sendable {
    case username
    case focus
    case submit
    case documentState

    /// The focused field moved under the prompt already on show — the page
    /// scrolled, the window resized, or the reader changed the page's zoom.
    /// It carries geometry and nothing else, so it can never open a prompt,
    /// only move one.
    case fieldGeometry
}
