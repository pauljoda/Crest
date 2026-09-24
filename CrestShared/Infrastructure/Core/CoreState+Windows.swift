import Foundation

extension CoreState {
    func apply(_ change: WindowChanged) {
        windows[change.window.id] = change.window
    }

    func apply(_ change: WindowClosed) {
        windows[change.windowID] = nil
    }

    /// The sidebar values the adopted records carried are the platform's own;
    /// the read model keeps nothing of the adoption.
    func apply(_ change: WindowRecordsAdopted) {}
}
