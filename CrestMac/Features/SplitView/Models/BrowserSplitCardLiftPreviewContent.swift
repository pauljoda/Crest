import AppKit
import CoreGraphics

/// Everything the floating preview window needs to draw a carried Split View
/// card, as one comparable value.
///
/// Resolved where the Space is already in hand, the way the sidebar's own lift
/// subject is: the carry holds a `TabID` and a picture, and the preview shows a
/// real tab's title and favicon while the picture is still on its way. One value
/// rather than a handful of properties so the window host can tell a frame that
/// changed something from a frame that changed nothing.
struct BrowserSplitCardLiftPreviewContent: Equatable {
    let tab: BrowserTab
    /// The Space profile the fallback art resolves the favicon against.
    let profileID: UUID
    /// The page as it was rendered at pickup, once WebKit has handed it over.
    let snapshot: NSImage?
    /// Top-left of the card, in the window-global space the preview window is
    /// pinned to.
    let origin: CGPoint
    let size: CGSize
    /// Where inside the card the pointer took hold. The rise is scaled about
    /// this point, so the pixel somebody grabbed stays under the cursor.
    let grabFraction: CGPoint
    /// True while the preview is fading onto the slot the card has already
    /// returned to.
    let isSettling: Bool
    /// Passed in rather than read from the environment: the preview is hosted in
    /// a window of its own, which inherits nothing from the browser's.
    let reduceMotion: Bool
}
