import AppKit

// MARK: - Types

/// A clear of a Space's open tabs while the window's Undo holds it, which
/// takes it back once, from Edit › Undo or from the notice. The undo action
/// registered for it keeps it; the notice only refers to it.
@MainActor
private final class BrowserTabsClearUndo {
    let clearing: BrowserTabsClearing
    var isTakenBack = false
    /// The notice that offers it, which goes once it is taken back.
    var notice: BrowserNotice?

    init(_ clearing: BrowserTabsClearing) {
        self.clearing = clearing
    }
}

// MARK: - Clear Undo

extension BrowserRootModel: BrowserTabsClearUndoing {
    /// Offers to take back `clearing` from this window's Edit › Undo, named
    /// for the command that cleared, and from the notice that reports it.
    func offerUndo(of clearing: BrowserTabsClearing) {
        guard let undoManager = pages.presentationWindow?.undoManager else { return }
        let undo = BrowserTabsClearUndo(clearing)
        register(undo, in: undoManager)
        let notice = BrowserNotice.tabsCleared { [weak self, weak undo, weak undoManager] in
            guard let self, let undo, let undoManager, !undo.isTakenBack else { return }
            undoManager.removeAllActions(withTarget: undo)
            self.takeBack(undo, in: undoManager)
        }
        undo.notice = notice
        chrome.showNotice(notice)
    }

    /// Offers `undo` as this window's Undo, whose action keeps it until it
    /// runs or the undo manager lets it go.
    private func register(_ undo: BrowserTabsClearUndo, in undoManager: UndoManager) {
        undoManager.registerUndo(withTarget: undo) { [weak self, weak undoManager, undo] _ in
            guard let undoManager else { return }
            self?.takeBack(undo, in: undoManager)
        }
        undoManager.setActionName(undo.clearing.command.title())
        (pages.presentationWindow as? BrowserMacWindow)?.undoLeadsPage = true
    }

    /// Takes `undo`'s clear back once: the core opens its tabs again where
    /// they stood, the window shows its pages and the notice goes. Undone
    /// from Edit › Undo, Redo clears the Space again. Refused, the notice says
    /// why, and a refusal that may pass, such as a failed save, leaves Undo
    /// to try again.
    private func takeBack(_ undo: BrowserTabsClearUndo, in undoManager: UndoManager) {
        guard !undo.isTakenBack else { return }
        do {
            try browser.restoreClearedTabs(undo.clearing)
        } catch {
            let gone = error.clearedTabsGone != nil
            undo.isTakenBack = gone
            let reason = error.message ?? ClearedTabsGone(clearID: undo.clearing.id).message
            chrome.showNotice(.failure(String(localized: reason)))
            // Registered while undoing, Undo would land on the redo stack.
            if !gone {
                DispatchQueue.main.async { [weak self, weak undoManager] in
                    guard let self, let undoManager else { return }
                    self.register(undo, in: undoManager)
                }
            }
            return
        }
        undo.isTakenBack = true
        if let notice = undo.notice { chrome.notices.dismiss(notice) }
        undo.notice = nil
        pages.reconcile()
        pages.select()
        guard undoManager.isUndoing else { return }
        let clearing = undo.clearing
        undoManager.registerUndo(withTarget: self) { model in model.clearAgain(clearing) }
        undoManager.setActionName(clearing.command.title())
        (pages.presentationWindow as? BrowserMacWindow)?.undoLeadsPage = true
    }

    /// Clears `clearing`'s Space again, as Redo does, which offers its own
    /// Undo.
    private func clearAgain(_ clearing: BrowserTabsClearing) {
        guard browser.clearCurrentTabs(matching: clearing.space, keepingShownTab: clearing.keepsShownTab) else {
            return
        }
        pages.reconcile()
        pages.select()
    }
}
