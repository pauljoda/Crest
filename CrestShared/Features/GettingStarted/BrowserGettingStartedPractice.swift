import Observation
import SwiftUI

/// A completely separate store family with memory-only persistence. Reusing the
/// real sidebar here must never let a practice gesture reach the person's tabs.
@Observable @MainActor
final class BrowserGettingStartedPractice {
    let browser: BrowserStore
    let spaceAccess = BrowserSpaceAccessController()
    let downloads = BrowserDownloadCenter(
        permissionCenter: BrowserSitePermissionCenter(persistence: InMemoryBrowserSitePermissionPersistence()))
    let mailID: TabID
    let trailID: TabID
    let packingID: TabID
    private let seed: BrowserSession

    init() {
        let calendar = BrowserTab(
            title: "Calendar", url: URL(string: "https://calendar.google.com"),
            faviconData: BrowserGettingStartedArtwork.favicon("GuideCalendar"), placement: .pinned)
        let reading = BrowserTab(
            title: "Wikipedia", url: URL(string: "https://wikipedia.org"),
            faviconData: BrowserGettingStartedArtwork.favicon("GuideWikipedia"), placement: .saved
        )
        let mail = BrowserTab(
            title: "Gmail", url: URL(string: "https://mail.google.com"),
            faviconData: BrowserGettingStartedArtwork.favicon("GuideGmail"), placement: .current)
        let trail = BrowserTab(
            title: "A weekend away", url: URL(string: "https://www.alltrails.com"),
            faviconData: BrowserGettingStartedArtwork.favicon("GuideAllTrails"),
            placement: .current)
        let packing = BrowserTab(
            title: "Packing list", url: URL(string: "https://todoist.com"),
            faviconData: BrowserGettingStartedArtwork.favicon("GuideTodoist"), placement: .current
        )
        mailID = mail.id
        trailID = trail.id
        packingID = packing.id
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Practice", symbol: "leaf.fill", accent: .indigo,
            branding: .house(.winter, symbol: "leaf.fill"), folders: [],
            tabs: [calendar, reading, mail, trail, packing], selectedTabID: trail.id)
        seed = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        browser = BrowserStore(session: seed, persistence: InMemoryBrowserSessionPersistence())
    }

    var space: BrowserSpace { browser.session.spaces[0] }
    var assignment: BrowserSpaceRuntimeAssignment { BrowserSpaceRuntimeAssignment(space: space) }
    var members: [BrowserTab] { space.presentedSplitMembers(for: space.selectedTabID) }

    func reset() {
        _ = browser.sidebarReorderState.end()
        browser.session = seed
    }

    func addFolder(nested: Bool) {
        let parent =
            space.folders.first { $0.title == "Weekends" && $0.parentID == nil }?.id
            ?? browser.addFolder(title: "Weekends", in: space.id)
        if nested, let parent, !space.folders.contains(where: { $0.parentID == parent }) {
            _ = browser.addFolder(title: "Ideas", parentID: parent, in: space.id)
        }
    }

    func makeSplit() {
        guard space.tabs.contains(where: { $0.id == packingID }), space.tabs.contains(where: { $0.id == trailID })
        else { return }
        browser.selectTab(trailID)
        _ = browser.addTabToSplit(
            BrowserTabDragItem(tabID: packingID, spaceID: space.id, profileID: space.profile.id), joining: trailID,
            at: nil)
    }

    func openExampleTab() {
        guard let id = browser.openNewTab(url: URL(string: "https://wikipedia.org")!) else { return }
        browser.session.updateTab(
            url: URL(string: "https://wikipedia.org"), title: "Wikipedia",
            faviconData: BrowserGettingStartedArtwork.favicon("GuideWikipedia"), tabID: id, in: space.id)
    }

    func move(_ id: TabID, by offset: Int) {
        browser.selectTab(id)
        _ = browser.moveSplitMember(id, by: offset, matching: assignment)
    }

    func moveFocused(by offset: Int) {
        guard let id = space.selectedTabID else { return }
        _ = browser.moveSplitMember(id, by: offset, matching: assignment)
    }

    var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(
            containsResidentPage: { _ in true }, containsResidentPageMatching: { _ in true },
            siteThemeIconAccent: { _ in nil }, residencyRevision: { 0 }, selectPages: {},
            deactivatePagePresentation: {}, unloadPage: { _, _ in }, pullFavicon: { _, _ in nil },
            downloadCenter: downloads)
    }

    var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: assignment, browser: browser, spaceAccess: spaceAccess,
            syncPagesAfterMutation: {}, pullFavicon: { _, _ in nil })
    }
}
