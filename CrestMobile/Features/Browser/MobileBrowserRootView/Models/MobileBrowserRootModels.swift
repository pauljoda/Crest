import Foundation

// MARK: - Presentation

enum MobileStartPageForegroundTone: Equatable, Sendable {
    case onBrand
}

struct MobileTabPromotionTarget: Equatable {
    let tabID: UUID
    let placement: TabPlacement
}

// MARK: - Snapshots

struct MobileBrowserRootLockSnapshot: Equatable, Sendable {
    let sessionRevision: BrowserSessionRevision
    let selectedSpaceID: UUID
    let selectedProfileID: UUID?
    let isLocked: Bool
    let presentation: MobileBrowserPresentation
}

struct MobileBrowserRootSelectionSnapshot: Equatable, Sendable {
    let sessionRevision: BrowserSessionRevision
    let selectedSpaceID: UUID
    let selectedProfileID: UUID?
    let assignment: BrowserTabRuntimeAssignment?
}
