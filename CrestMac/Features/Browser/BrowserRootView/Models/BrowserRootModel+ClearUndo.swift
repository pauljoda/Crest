import AppKit

// MARK: - Types

/// A clear of a Space's open tabs while the window's Undo holds it, which
/// takes it back once, from Edit › Undo or from the notice.
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
        guard let window = pages.presentationWindow, let undoManager = window.undoManager else { return }
        let undo = BrowserTabsClearUndo(clearing)
        undoManager.registerUndo(withTarget: undo) { [weak self, weak undoManager] undo in
            guard let undoManager else { return }
            self?.takeBack(undo, in: undoManager)
        }
        undoManager.setActionName(clearing.command.title())
        (window as? BrowserMacWindow)?.undoLeadsPage = true
        let notice = BrowserNotice.tabsCleared { [weak self, weak undoManager] in
            guard let self, let undoManager, !undo.isTakenBack else { return }
            undoManager.removeAllActions(withTarget: undo)
            self.takeBack(undo, in: undoManager)
        }
        undo.notice = notice
        chrome.showNotice(notice)
    }

    /// Takes `undo`'s clear back once: the core opens its tabs again where
    /// they stood and the window shows its pages. Undone from Edit › Undo,
    /// Redo clears the Space again; refused, the notice says why.
    private func takeBack(_ undo: BrowserTabsClearUndo, in undoManager: UndoManager) {
        guard !undo.isTakenBack else { return }
        undo.isTakenBack = true
        if let notice = undo.notice { chrome.notices.dismiss(notice) }
        do {
            try browser.restoreClearedTabs(undo.clearing)
        } catch {
            let reason = error.message ?? ClearedTabsGone(clearID: undo.clearing.id).message
            chrome.showNotice(.failure(String(localized: reason)))
            return
        }
        pages.reconcile()
        pages.select()
        guard undoManager.isUndoing else { return }
        let clearing = undo.clearing
        undoManager.registerUndo(withTarget: undo) { [weak self] _ in self?.clearAgain(clearing) }
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
