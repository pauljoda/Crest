import Foundation

/// How much of a window a Look and Feel preview shows.
///
/// The pinned preview shows the whole window; a group's own card shows only the
/// part that group changes, so the reader never has to hunt for what moved.
enum BrowserLookAndFeelPreviewFocus: Equatable {
    case window
    case page
    case tabs
    case addressField
    case folders
}
