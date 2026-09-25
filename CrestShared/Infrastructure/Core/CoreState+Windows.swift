import Foundation

extension CoreState {
    /// A window that stays open keeps its object, which notifies only for
    /// what it shows differently, so another window's change never reaches it.
    func apply(_ change: WindowChanged) {
        if let window = windows[change.window.id] {
            window.update(change.window)
        } else {
            publish(WindowStateModel(change.window), forKey: change.window.id, into: \.windowsStorage, as: \.windows)
        }
    }

    func apply(_ change: WindowClosed) {
        publish(nil, forKey: change.windowID, into: \.windowsStorage, as: \.windows)
    }

    /// The sidebar values the adopted records carried are the platform's own;
    /// the read model keeps nothing of the adoption.
    func apply(_ change: WindowRecordsAdopted) {}
}
