import Foundation

/// The real thing a floating lift is showing, resolved out of the Space.
///
/// The drag carries identifiers; a preview shows titles and favicons. Resolving
/// once, where the Space is already in hand, keeps the preview window a
/// presentation of the drag rather than a second place that has to look things
/// up — and keeps the three kinds of lift the sidebar can start from turning
/// into three kinds of art without anything downstream branching on drag state.
enum BrowserSidebarLiftPreviewSubject: Equatable {
    case tab(BrowserTab)
    case folder(SavedFolder)
    /// A whole split group, in member order.
    case splitGroup([BrowserTab])
}
