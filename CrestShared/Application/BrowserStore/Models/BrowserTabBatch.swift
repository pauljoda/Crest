import Foundation

/// One action on the tabs and folders a window's sidebar selected: the intent
/// the window sends the core, and what the window does once the core accepts
/// it. `BrowserStore` makes one for each action; see `BrowserStore+TabBatch`.
struct BrowserTabBatch {
    // MARK: - Types

    /// What the window's multi-selection holds once the action is done.
    enum Reselection {
        /// Nothing: the selected tabs left the window's list.
        case cleared
        /// The copies the action made.
        case copies
        /// The same items, a copy standing in for each source the action copied.
        case items
    }

    // MARK: - Variables

    let intent: any Intent
    let reselection: Reselection
    /// Whether the action closes the selected tabs' pages, which may first
    /// ask the person to leave them.
    let closesPages: Bool
    /// The Space the window follows the tabs to, when it does.
    let following: BrowserSpaceRuntimeAssignment?

    // MARK: - Initializers

    init(
        _ intent: any Intent, reselection: Reselection, closesPages: Bool = false,
        following: BrowserSpaceRuntimeAssignment? = nil
    ) {
        self.intent = intent
        self.reselection = reselection
        self.closesPages = closesPages
        self.following = following
    }
}
