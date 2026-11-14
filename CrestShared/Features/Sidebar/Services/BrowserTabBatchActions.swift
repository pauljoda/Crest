import Foundation

/// Performs a window's actions on the selection its sidebar captured. Whether
/// an action is offered, and what the person is told when one is refused, are
/// the core's answers; closing pages first asks the person to leave them.
@MainActor
struct BrowserTabBatchActions {
    // MARK: - Variables

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    // MARK: - Actions - Performing

    /// Whether the core would take the action now.
    func isAvailable(_ batch: BrowserTabBatch) -> Bool { browser.canSend(batch) }

    /// What the person is told the action would be refused for, or nil when
    /// the core would take it.
    func reason(_ batch: BrowserTabBatch) -> String? { browser.refusal(of: batch)?.placementExplanation }

    /// Performs the action, and answers whether the core took it; a refusal
    /// is shown in the selection's message instead.
    @discardableResult
    func perform(_ batch: BrowserTabBatch, for request: BrowserCapturedSelection) -> Bool {
        guard batch.closesPages else { return send(batch, for: request) }
        if let reason = reason(batch) {
            browser.tabMultiSelection.message = reason
            return false
        }
        let assignments = request.ids.map {
            BrowserTabRuntimeAssignment(
                tabID: $0, spaceID: request.assignment.spaceID, profileID: request.assignment.profileID)
        }
        return browser.performPageDismissal(of: assignments) { send(batch, for: request) }
    }

    /// Performs an action that makes a folder, and answers the folder the core
    /// made, so the sidebar can open its name for editing. A folder action
    /// leaves every page where it is, so it asks nobody to leave one; a
    /// refusal is shown in the selection's message, as `perform` shows it.
    func performCreatingFolder(_ batch: BrowserTabBatch, for request: BrowserCapturedSelection) -> UUID? {
        do {
            return try browser.send(batch, for: request)
        } catch {
            browser.tabMultiSelection.message = error.placementExplanation
            return nil
        }
    }

    private func send(_ batch: BrowserTabBatch, for request: BrowserCapturedSelection) -> Bool {
        do {
            try browser.send(batch, for: request)
            return true
        } catch {
            browser.tabMultiSelection.message = error.placementExplanation
            return false
        }
    }

    /// Copies the selected pages' addresses, when every selected tab is a
    /// page the core would keep loaded.
    func copyLinks(_ request: BrowserCapturedSelection) {
        if let reason = reason(browser.keepingLoaded(request, false)) {
            browser.tabMultiSelection.message = reason
            return
        }
        let links = BrowserTabOrganizationAction(browser: browser, spaceAccess: spaceAccess)
        var copied: [BrowserCopiedLink] = []
        for id in request.ids {
            guard
                let url = links.linkURL(
                    for: BrowserTabRuntimeAssignment(
                        tabID: id, spaceID: request.assignment.spaceID, profileID: request.assignment.profileID))
            else {
                browser.tabMultiSelection.message =
                    Rejection.webPagesOnly(WebPagesOnly(tabID: id)).placementExplanation
                return
            }
            copied.append(browser.core.linkToCopy(url))
        }
        BrowserPageLinkClipboard.copy(copied)
    }
}
