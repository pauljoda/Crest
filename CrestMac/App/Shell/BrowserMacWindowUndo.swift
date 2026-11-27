import AppKit

/// Edit › Undo or Redo taken by the key browser window's own undo manager
/// rather than the focused page. The window's undo manager holds what its
/// browser commands registered, such as a clear of a Space's open tabs, with
/// the edits of its text fields and WebKit pages, which register there too.
/// Chromium's page view keeps its page's edits to itself and answers Undo and
/// Redo for them, so it would hide a command the person just ran: until the
/// page takes another key, the window's own action comes first.
@MainActor
struct BrowserMacWindowUndo {
    // MARK: - Static Variables

    static let undo = Selector(("undo:"))
    static let redo = Selector(("redo:"))

    // MARK: - Variables

    private let manager: UndoManager
    private let redoes: Bool

    /// What the menu item says, as the undo manager names its action.
    var title: String { redoes ? manager.redoMenuItemTitle : manager.undoMenuItemTitle }

    // MARK: - Initializers

    /// The window's own Undo, or Redo for `redo:`, while `window`'s focused
    /// page answers `action` itself and the window's own action came after the
    /// page last took a key; nil where AppKit's route applies.
    init?(_ action: Selector?, in window: NSWindow?) {
        guard let action, action == Self.undo || action == Self.redo,
            let window = window as? BrowserMacWindow, window.undoLeadsPage,
            let responder = window.firstResponder, BrowserWebHostView.isPageContent(responder),
            responder.responds(to: action), let manager = window.undoManager
        else { return nil }
        let redoes = action == Self.redo
        guard redoes ? manager.canRedo : manager.canUndo else { return nil }
        self.manager = manager
        self.redoes = redoes
    }

    // MARK: - Actions - Keys

    /// Whether `event` is the Undo or Redo chord, ⌘Z or ⇧⌘Z, which leave the
    /// window's own action first.
    static func isUndoOrRedo(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return event.charactersIgnoringModifiers?.lowercased() == "z"
            && (modifiers == .command || modifiers == [.command, .shift])
    }

    // MARK: - Actions - Running

    func perform() {
        if redoes { manager.redo() } else { manager.undo() }
    }
}
