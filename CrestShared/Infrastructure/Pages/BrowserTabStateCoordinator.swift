import Foundation

/// Owns session-state eligibility and the states tabs' next pages open with,
/// without retaining pages. The platform supplies a page only while capturing
/// its opaque engine state.
@MainActor
final class BrowserTabStateCoordinator {
    // MARK: - Variables

    private let archive: (any BrowserTabStateArchiving)?
    /// What a tab's next page opens with, by tab: the state a copy was given
    /// before its first page opened, or the archive read ahead of the open,
    /// as the core took the tab's history back, so the page restores the
    /// state that read decoded instead of reading the archive again.
    private var pendingStates: [BrowserTabRuntimeAssignment: BrowserTabStateEnvelope] = [:]
    private var lastPrunedTabIDsByProfileID: [UUID: Set<UUID>] = [:]

    var archivesResidentPages: Bool { archive != nil }

    // MARK: - Initializers

    init(archive: (any BrowserTabStateArchiving)?) {
        self.archive = archive
    }

    // MARK: - Actions - Pending states

    func retainCopies(for tabIDs: Set<UUID>) {
        pendingStates = pendingStates.filter { tabIDs.contains($0.key.tabID) }
    }

    func retainCopies(matching assignments: Set<BrowserTabRuntimeAssignment>) {
        pendingStates = pendingStates.filter { assignments.contains($0.key) }
    }

    /// Keeps what the copy `assignment` opens with: its engine state, the
    /// core's history, or both. A page with no engine state yet still has the
    /// history the core keeps for it.
    func prepareCopy(_ state: Data?, url: URL?, history: Data?, for assignment: BrowserTabRuntimeAssignment) {
        guard state != nil || history != nil else { return }
        pendingStates[assignment] = BrowserTabStateEnvelope(
            interactionState: state ?? Data(), url: url, history: history)
    }

    // MARK: - Actions - Archiving

    func archivePage(_ page: BrowserPlatformPage, for tabID: UUID) {
        archivePage(page, showing: page.live.documentURL, for: tabID)
    }

    /// Archives the page's state as showing `url`, for a page whose live state
    /// the core no longer holds.
    func archivePage(_ page: BrowserPlatformPage, showing url: URL?, for tabID: UUID) {
        // WebKit drives adopted popups; they are never persisted as user tabs.
        guard let archive, !page.wasOpenedAsPopup else { return }
        // The page's own state is newer than anything read ahead of its open.
        pendingStates = pendingStates.filter { $0.key.tabID != tabID }
        // The core keeps the page's history whether or not its engine has
        // state to keep yet, as before its first document commits. Such a
        // page keeps the engine state its archive already holds, so an empty
        // renderer never replaces a useful one.
        let history = page.corePage.archivedHistory
        var state = page.interactionState
        var shown = url
        if state == nil, history != nil,
            let kept = archive.archivedState(profileID: page.profileID, tabID: tabID)
                .flatMap(BrowserTabStateEnvelope.decode),
            kept.isRestorable
        {
            state = kept.interactionState
            shown = kept.url
        }
        guard state != nil || history != nil else { return }
        archive.archive(
            interactionState: state ?? Data(),
            url: shown,
            history: history,
            profileID: page.profileID,
            tabID: tabID
        )
    }

    // MARK: - Actions - Restoring

    /// The back and forward history the tab's pending state or archive keeps,
    /// when it still shows `url`, which the core takes back before the tab's
    /// page opens. Leaves the engine history for the page to restore.
    func history(for assignment: BrowserTabRuntimeAssignment, expecting url: URL) -> Data? {
        envelope(for: assignment, expecting: url, consumePendingCopy: false)?.history
    }

    func interactionState(
        for assignment: BrowserTabRuntimeAssignment,
        expecting url: URL,
        consumePendingCopy: Bool = true
    ) -> Data? {
        guard let envelope = envelope(for: assignment, expecting: url, consumePendingCopy: consumePendingCopy),
            envelope.isRestorable
        else { return nil }
        return envelope.interactionState
    }

    /// What the tab's pending state keeps, or else its archive, when it still
    /// shows `url`. A read that leaves the pending state in place runs ahead
    /// of the tab's open, so what it reads from the archive waits there for
    /// the page that opens.
    private func envelope(
        for assignment: BrowserTabRuntimeAssignment,
        expecting url: URL,
        consumePendingCopy: Bool
    ) -> BrowserTabStateEnvelope? {
        let pending = pendingStates[assignment]
        if consumePendingCopy { pendingStates.removeValue(forKey: assignment) }
        if let pending,
            SamePage.restoresArchivedState(archivedURL: pending.url, tabURL: url)
        {
            return pending
        }
        guard let archive,
            let archived = archive.archivedState(profileID: assignment.profileID, tabID: assignment.tabID),
            let envelope = BrowserTabStateEnvelope.decode(archived),
            envelope.isReadable,
            SamePage.restoresArchivedState(archivedURL: envelope.url, tabURL: url)
        else { return nil }
        if !consumePendingCopy { pendingStates[assignment] = envelope }
        return envelope
    }

    // MARK: - Actions - Removing

    /// Only membership changes warrant another directory sweep. Closed tabs
    /// retain state until they leave both the live and archived tab collections.
    func prune(keeping tabIDsByProfileID: [UUID: Set<UUID>]) {
        guard let archive, !tabIDsByProfileID.isEmpty,
            tabIDsByProfileID != lastPrunedTabIDsByProfileID
        else { return }
        lastPrunedTabIDsByProfileID = tabIDsByProfileID
        archive.pruneStates(keeping: tabIDsByProfileID)
    }

    func discardState(matching assignment: BrowserTabRuntimeAssignment) {
        pendingStates.removeValue(forKey: assignment)
        removeState(profileID: assignment.profileID, tabID: assignment.tabID)
    }

    func removeState(profileID: UUID, tabID: UUID) {
        archive?.removeState(profileID: profileID, tabID: tabID)
    }

    func removeStates(profileID: UUID) {
        archive?.removeStates(profileID: profileID)
    }

    func flushPendingWrites() async {
        await archive?.flushPendingWrites()
    }
}
