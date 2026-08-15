import Foundation

extension BrowserExtensionTabWindowCoordinator {

    /// Announces a page the session does not carry, so extensions can answer
    /// the content scripts WebKit is about to run inside it.
    ///
    /// Register before the page begins its first navigation. WebKit injects a
    /// document-start content script during that load and resolves the messages
    /// it sends by mapping its web view onto an announced tab; a script that
    /// asks its background for configuration before the announcement is
    /// rejected outright rather than queued, and nothing retries it for the life
    /// of that document.
    func registerTransientTab(
        _ tab: BrowserExtensionTransientTab,
        in spaceID: SpaceID
    ) {
        var transient = transientTabsBySpace[spaceID] ?? []
        if let existing = transient.firstIndex(where: { $0.id == tab.id }) {
            transient[existing] = tab
        } else {
            transient.append(tab)
        }
        transientTabsBySpace[spaceID] = transient
        reconcileCurrentSession()
    }

    /// Withdraws a transient page, closing the tab extensions were told about.
    ///
    /// The page is gone either way — released, evicted under memory pressure, or
    /// handed to a real tab that announces itself — so leaving the announcement
    /// standing would be the dishonest outcome.
    func unregisterTransientTab(_ tabID: TabID, in spaceID: SpaceID) {
        guard var transient = transientTabsBySpace[spaceID],
            transient.contains(where: { $0.id == tabID })
        else { return }
        transient.removeAll { $0.id == tabID }
        if transient.isEmpty {
            transientTabsBySpace.removeValue(forKey: spaceID)
        } else {
            transientTabsBySpace[spaceID] = transient
        }
        reconcileCurrentSession()
    }

    /// Re-runs the diff against the session already in hand.
    ///
    /// Transient pages appear and disappear without the session changing at all,
    /// so they have no store update to ride in on.
    func reconcileCurrentSession() {
        guard let browser else { return }
        reconcile(session: browser.session)
    }
}
