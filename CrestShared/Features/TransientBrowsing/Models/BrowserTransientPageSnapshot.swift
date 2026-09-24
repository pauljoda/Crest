import Foundation

struct BrowserTransientPageSnapshot: Equatable, Sendable {
    let assignment: BrowserSpaceRuntimeAssignment
    let url: URL
    let title: String?
    /// The core page that last showed it, which may be gone.
    let pageID: UUID
}
