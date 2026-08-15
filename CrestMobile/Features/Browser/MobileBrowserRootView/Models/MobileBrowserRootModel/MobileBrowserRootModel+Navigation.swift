import SwiftUI

extension MobileBrowserRootModel {
    func selectTab(_ id: TabID) {
        browser.selectTab(id)
        pages.select(session: browser.session)
        address = browser.selectedTab?.url?.absoluteString ?? ""
        navigation.selectTab()
    }

    @discardableResult
    func submitAddress() -> Bool {
        guard
            let url = AddressResolver.resolve(
                address,
                searchProvider: browser.selectedSpace?.browsingPreferences.searchProvider
                    ?? .google
            )
        else { return false }
        browser.navigateSelectedTab(to: url)
        pages.select(session: browser.session)
        pages.load(url)
        address = url.absoluteString
        navigation.selectTab()
        return true
    }

    func openURL(_ url: URL) {
        browser.openNewTab(url: url)
        pages.select(session: browser.session)
        address = url.absoluteString
        navigation.selectTab()
    }

    func beginCompactNewTab() {
        browser.openNewTab()
        pages.select(session: browser.session)
        address = ""
        navigation.selectTab()
    }

    func showTabViewer() {
        navigation.dismissPageToTabViewer()
    }

    func activateSelectedTab() {
        pages.select(session: browser.session)
        address = browser.selectedTab?.url?.absoluteString ?? ""
        navigation.selectTab()
    }

    func switchSpace(
        _ direction: BrowserSpaceSwipeDirection,
        reduceMotion: Bool
    ) {
        withAnimation(accessibleAnimation(CrestMotion.navigation, reduceMotion)) {
            guard browser.selectAdjacentSpace(direction) != nil else { return }
            pages.select(session: browser.session)
            address = browser.selectedTab?.url?.absoluteString ?? ""
        }
    }

    func focusStartPageAddress() {
        address = ""
    }

}
