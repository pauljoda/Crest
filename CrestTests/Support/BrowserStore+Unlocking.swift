import Foundation

@testable import Crest

extension BrowserStore {
    /// Unlocks `space` in the core, as the device owner's authentication does,
    /// for a test that shows or edits a protected Space. The core keeps every
    /// protected Space locked until then, whatever the views believe.
    func unlockForTesting(_ space: BrowserSpace) {
        let request = UUID()
        _ = try? core.send(
            BeginUnlockingSpace(workspaceID: family.workspaceID, spaceID: space.id.rawValue, requestID: request))
        _ = try? core.send(FinishUnlockingSpace(spaceID: space.id.rawValue, requestID: request, authenticated: true))
    }

    /// Whether this window's session is the one whose journal syncs: only the
    /// session the core keeps in its file does.
    var syncsSession: Bool {
        core.state.syncJournal?.workspaceID == family.workspaceID
    }
}
