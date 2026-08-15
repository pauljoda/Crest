import Foundation

struct MobileBrowserTransientRenderIdentity: Hashable {
    let requestID: UUID
    let url: URL
    let assignment: BrowserSpaceRuntimeAssignment
    let isQuickWindow: Bool
}
