import Foundation

struct BrowserTransientPageSnapshot: Equatable, Sendable {
    let assignment: BrowserSpaceRuntimeAssignment
    let url: URL
    let title: String?
}
