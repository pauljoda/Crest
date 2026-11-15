import CoreGraphics
import Foundation

/// What a window draws over its Split View cards: the floating sidebar, and the
/// card and controls of the Peek it shows. A pointer there is using that
/// chrome, not the card beneath, so it neither focuses nor hovers that card. A
/// Peek shows only over the card it came from, so focusing the card beneath
/// one would hide it.
///
/// Not `@Observable`, as `BrowserSplitCardFrameRegistry` is not: the frames
/// are written during layout and read only when the pointer arrives.
@MainActor
final class BrowserSplitCoveringChrome {
    // MARK: - Types

    /// Where one drawn Peek stands, and the request it shows.
    private struct Peek {
        let request: BrowserPeekRequest
        let frame: CGRect
    }

    // MARK: - Variables

    /// Where the sidebar's surface stands in the window, in the global space.
    /// A hidden sidebar is only moved out of sight, so the frame counts only
    /// while the sidebar floats.
    var sidebarFrame = CGRect.null
    /// Where each drawn Peek's card and controls stand, by request. Every
    /// Space's pages may be drawn at once, so a Peek counts only while the
    /// window shows it.
    private var peeks: [UUID: Peek] = [:]

    // MARK: - Actions - Reading

    /// Whether chrome stands over `point`, in the window's global space: the
    /// sidebar while `presentation` floats it, or a Peek `browser` shows.
    func covers(_ point: CGPoint, sidebar presentation: BrowserSidebarPresentation, in browser: BrowserStore) -> Bool {
        (presentation == .floating && sidebarFrame.contains(point))
            || peeks.values.contains { $0.request.isSelected(in: browser) && $0.frame.contains(point) }
    }

    // MARK: - Mutators

    /// Records where the Peek of `request` stands, or that it is no longer
    /// drawn.
    func record(_ request: BrowserPeekRequest, frame: CGRect?) {
        peeks[request.id] = frame.map { Peek(request: request, frame: $0) }
    }
}
