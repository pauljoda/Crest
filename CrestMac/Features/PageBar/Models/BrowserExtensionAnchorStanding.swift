import SwiftUI

/// How strongly a control stands for the window's extension actions when
/// nothing was clicked: a keyboard shortcut or a page asking an engine for an
/// extension's popup opens it at the strongest control the window shows.
///
/// A split's cards each carry the extension tiles and Site Controls the window
/// shows, so the focused card's come first, then the window's own in the
/// sidebar or its address bar, then the other cards'.
enum BrowserExtensionAnchorStanding: Int, Comparable {
    /// A control in a split card that does not have focus.
    case unfocusedCard
    /// The window's own controls, in the sidebar or its address bar.
    case window
    /// A control in the bar of the split card that has focus.
    case focusedCard

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension EnvironmentValues {
    /// The standing of the extension controls below: the window's own unless
    /// a split card's bar says otherwise.
    @Entry var browserExtensionAnchorStanding = BrowserExtensionAnchorStanding.window
}

/// A native view an engine anchors extension popups to, which carries the
/// standing of the control it sits behind.
@MainActor
protocol BrowserExtensionAnchorStandingView: NSView {
    var standing: BrowserExtensionAnchorStanding { get set }
}
