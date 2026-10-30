import Foundation

/// A one-time code a prompt offers for the field that asked. It names whose
/// code it is, never the code: the value stays with whoever issued the row
/// until the person picks it.
struct BrowserOneTimeCodeSuggestion: Equatable, Identifiable, Sendable {
    let id: UUID
    let username: String?
}
