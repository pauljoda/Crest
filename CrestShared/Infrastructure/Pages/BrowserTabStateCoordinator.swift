import Foundation

/// Owns session-state eligibility and pending copies without retaining pages.
/// The platform supplies a page only while capturing its opaque engine state.
@MainActor
final class BrowserTabStateCoordinator {
    private let archive: (any BrowserTabStateArchiving)?
    private var pendingCopies: [BrowserTabRuntimeAssignment: BrowserTabStateEnvelope] = [:]
    private var lastPrunedTabIDsByProfileID: [UUID: Set<TabID>] = [:]

    var archivesResidentPages: Bool { archive != nil }

    init(archive: (any BrowserTabStateArchiving)?) {
        self.archive = archive
    }

    func retainCopies(for tabIDs: Set<TabID>) {
        pendingCopies = pendingCopies.filter { tabIDs.contains($0.key.tabID) }
    }

    func retainCopies(matching assignments: Set<BrowserTabRuntimeAssignment>) {
        pendingCopies = pendingCopies.filter { assignments.contains($0.key) }
    }

    func prepareCopy(_ state: Data, url: URL?, for assignment: BrowserTabRuntimeAssignment) {
        pendingCopies[assignment] = BrowserTabStateEnvelope(interactionState: state, url: url)
    }

    func archivePage(_ page: BrowserPlatformPage, for tabID: TabID) {
        // WebKit drives adopted popups; they are never persisted as user tabs.
        guard let archive, !page.wasOpenedAsPopup, let state = page.interactionState else { return }
        archive.archive(
            interactionState: state,
            url: page.live.documentURL,
            profileID: page.profileID,
            tabID: tabID
        )
    }

    func interactionState(
        for assignment: BrowserTabRuntimeAssignment,
        expecting url: URL,
        consumePendingCopy: Bool = true
    ) -> Data? {
        let pending = pendingCopies[assignment]
        if consumePendingCopy { pendingCopies.removeValue(forKey: assignment) }
        if let pending,
            BrowserTabStateRestorePolicy.restoresArchivedState(archivedURL: pending.url, tabURL: url)
        {
            return pending.interactionState
        }
        guard let archive,
            let archived = archive.archivedState(profileID: assignment.profileID, tabID: assignment.tabID),
            let envelope = BrowserTabStateEnvelope.decode(archived),
            envelope.isRestorable,
            BrowserTabStateRestorePolicy.restoresArchivedState(archivedURL: envelope.url, tabURL: url)
        else { return nil }
        return envelope.interactionState
    }

    /// Only membership changes warrant another directory sweep. Closed tabs
    /// retain state until they leave both the live and archived tab collections.
    func prune(keeping tabIDsByProfileID: [UUID: Set<TabID>]) {
        guard let archive, !tabIDsByProfileID.isEmpty,
            tabIDsByProfileID != lastPrunedTabIDsByProfileID
        else { return }
        lastPrunedTabIDsByProfileID = tabIDsByProfileID
        archive.pruneStates(keeping: tabIDsByProfileID)
    }

    func discardState(matching assignment: BrowserTabRuntimeAssignment) {
        pendingCopies.removeValue(forKey: assignment)
        removeState(profileID: assignment.profileID, tabID: assignment.tabID)
    }

    func removeState(profileID: UUID, tabID: TabID) {
        archive?.removeState(profileID: profileID, tabID: tabID)
    }

    func removeStates(profileID: UUID) {
        archive?.removeStates(profileID: profileID)
    }

    func flushPendingWrites() async {
        await archive?.flushPendingWrites()
    }
}
