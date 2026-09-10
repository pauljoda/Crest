import Foundation

@MainActor
struct BrowserTabBatchActions {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    func validate(_ request: BrowserTabBatchRequest, action: BrowserTabBatchAction) throws {
        guard
            BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: request.assignment, in: browser, accessController: spaceAccess) != nil
        else { throw BrowserTabBatchError.lockedSpace }
        if case .moveToSpace(let destination) = action,
            BrowserSidebarAccessPolicy.unlockedSpace(matching: destination, in: browser, accessController: spaceAccess)
                == nil
        {
            throw BrowserTabBatchError.lockedSpace
        }
        _ = try browser.prepareTabBatch(request, action: action)
    }

    func reason(_ request: BrowserTabBatchRequest, action: BrowserTabBatchAction) -> String? {
        do {
            try validate(request, action: action)
            return nil
        } catch { return message(for: error) }
    }

    @discardableResult
    func perform(_ request: BrowserTabBatchRequest, action: BrowserTabBatchAction) -> Bool {
        do {
            try validate(request, action: action)
            try browser.commitTabBatch(request, action: action)
            return true
        } catch {
            browser.tabMultiSelection.message = message(for: error)
            return false
        }
    }

    func message(for error: Error) -> String {
        switch error as? BrowserTabBatchError {
        case .folderActionUnavailable:
            String(
                localized:
                    "Move selected folders into saved or current tabs, or another folder. Use a folder’s own menu for other folder actions."
            )
        case .pinnedCapacity:
            String(localized: "A Space can hold up to 12 pinned tabs. Unpin tabs or select fewer tabs.")
        case .splitCapacity:
            String(localized: "Split View needs 2 to 4 tabs. Select fewer tabs or use a smaller split.")
        case .cannotPinSplit: String(localized: "Split View groups cannot be pinned. Separate the split first.")
        case .cannotMoveSplitAcrossSpaces:
            String(
                localized:
                    "Split View groups stay in their Space. Separate the split before moving it to another Space.")
        case .incompleteSplit: String(localized: "The split changed. Select the whole group again.")
        case .currentTabsOnly:
            String(
                localized:
                    "Archive applies to current tabs. Use Unload Pages to close saved or pinned pages, or Delete Tabs to remove their saved entries."
            )
        case .webPagesOnly: String(localized: "This action requires webpage tabs. Deselect built-in pages first.")
        case .lockedSpace:
            String(localized: "The Space is locked or no longer active. Unlock it and select the tabs again.")
        case .staleSelection: String(localized: "The selected items changed. Select them again before continuing.")
        default: String(localized: "These items cannot be placed here. Choose another destination.")
        }
    }

    func copyLinks(_ request: BrowserTabBatchRequest) {
        do {
            try validate(request, action: .keepLoaded(false))
            let links = BrowserTabOrganizationAction(browser: browser, spaceAccess: spaceAccess)
            let urls = request.ids.compactMap { id in
                links.linkURL(
                    for: BrowserTabRuntimeAssignment(
                        tabID: id, spaceID: request.assignment.spaceID, profileID: request.assignment.profileID))
            }
            guard urls.count == request.ids.count else { throw BrowserTabBatchError.webPagesOnly }
            BrowserPageLinkClipboard.copy(urls)
        } catch { browser.tabMultiSelection.message = message(for: error) }
    }
}
