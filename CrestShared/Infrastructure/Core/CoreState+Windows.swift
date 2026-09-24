import Foundation

extension CoreState {
    /// A window that stays open keeps its object, which notifies only for
    /// what it shows differently, so another window's change never reaches it.
    func apply(_ change: WindowChanged) {
        if let window = windows[change.window.id] {
            window.update(change.window)
        } else {
            windows[change.window.id] = WindowStateModel(change.window)
        }
    }

    func apply(_ change: WindowClosed) {
        windows[change.windowID] = nil
    }

    /// The sidebar values the adopted records carried are the platform's own;
    /// the read model keeps nothing of the adoption.
    func apply(_ change: WindowRecordsAdopted) {}
}
