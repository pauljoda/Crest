import Foundation

/// Everything the preview window draws for a lifted sidebar row, as one
/// comparable value.
///
/// The subject travels with the lift because the preview shows the real row —
/// title and favicon, or a folder, or a group's members — and the reorder state
/// carries only identifiers.
struct BrowserSidebarLiftPreviewContent: Equatable {
    let subject: BrowserSidebarLiftPreviewSubject
    let lift: BrowserSidebarFloatingLift
    /// Passed in rather than read from the environment: the preview is hosted in
    /// a window of its own, which inherits nothing from the browser's.
    let reduceMotion: Bool
    var selectedTabID: TabID?
    var loadedTabIDs: Set<TabID> = []
}
