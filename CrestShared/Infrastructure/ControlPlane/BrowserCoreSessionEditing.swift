import Foundation

/// Structural tab edits execute in .NET against the family's core session.
/// Their answers report only what the command made; the session's own changes
/// reach the Swift session copy through the core's change feed.
enum BrowserCoreSessionEditing {
    /// What a tab command made: the tab it opened or moved,
    /// the copies it made, whether it changed anything and whether a promoted
    /// page may move into its tab live.
    struct Result: Decodable {
        struct Copy: Decodable {
            var source: UUID
            var copy: UUID
        }
        var tabId: UUID?
        var copies: [Copy]
        var changed: Bool
        var adoptLivePage: Bool?
    }
}
