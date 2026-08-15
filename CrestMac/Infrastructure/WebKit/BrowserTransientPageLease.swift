import Dispatch
import Foundation
import Observation
import WebKit
import os

@Observable
@MainActor
final class BrowserTransientPageLease {
    let id = UUID()
    /// The identity this lease's page is announced under, so extensions can
    /// address the page the person is actually reading.
    let extensionTabID: TabID
    let spaceID: SpaceID
    let profileID: UUID
    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }
    private(set) var page: BrowserPage?
    private(set) var wasReleasedForMemoryPressure = false
    var recoverableURL: URL { page?.url ?? reloadURL }
    var canBeReused: Bool { page != nil || wasReleasedForMemoryPressure }

    @ObservationIgnored private(set) var isActive = true
    @ObservationIgnored private var reloadURL: URL
    @ObservationIgnored private let rebuild: () -> BrowserPage?
    @ObservationIgnored private let userActivity: () -> Void
    /// Reports the page now standing behind `extensionTabID`, or its absence.
    ///
    /// Called before a rebuilt page is navigated, because the announcement has
    /// to precede the load that injects content scripts into it.
    @ObservationIgnored private let extensionPageDidChange: (BrowserPage?) -> Void
    @ObservationIgnored private var contentBlockingPolicy: BrowserContentBlockingPolicy
    @ObservationIgnored private var balancedContentRuleLists: [WKContentRuleList]
    @ObservationIgnored private var isInvalidated = false

    init(
        extensionTabID: TabID,
        page: BrowserPage,
        url: URL,
        contentBlockingPolicy: BrowserContentBlockingPolicy,
        balancedContentRuleLists: [WKContentRuleList],
        rebuild: @escaping () -> BrowserPage?,
        userActivity: @escaping () -> Void,
        extensionPageDidChange: @escaping (BrowserPage?) -> Void = { _ in }
    ) {
        self.extensionTabID = extensionTabID
        self.page = page
        spaceID = page.spaceID
        profileID = page.profileID
        reloadURL = url
        self.contentBlockingPolicy = contentBlockingPolicy
        self.balancedContentRuleLists = balancedContentRuleLists
        self.rebuild = rebuild
        self.userActivity = userActivity
        self.extensionPageDidChange = extensionPageDidChange
        page.monitorUserActivity(userActivity)
        // The page is announced before this point, by whoever built it: this
        // load is what injects content scripts, and they cannot be answered
        // for a page extensions have not been told about.
        page.load(url)
    }

    func setActive(_ isActive: Bool) {
        self.isActive = isActive
    }

    func restore() {
        guard !isInvalidated, page == nil, let page = rebuild() else { return }
        page.applyContentBlocking(
            policy: contentBlockingPolicy,
            balancedRuleLists: balancedContentRuleLists
        )
        page.monitorUserActivity(userActivity)
        extensionPageDidChange(page)
        page.load(reloadURL)
        self.page = page
        wasReleasedForMemoryPressure = false
    }

    func releaseForMemoryPressure() {
        guard let page else { return }
        reloadURL = page.url ?? reloadURL
        page.prepareForSpaceDeletion()
        self.page = nil
        wasReleasedForMemoryPressure = true
        extensionPageDidChange(nil)
    }

    func release() {
        isInvalidated = true
        page?.prepareForSpaceDeletion()
        page = nil
        extensionPageDidChange(nil)
    }

    func applyContentBlocking(
        policy: BrowserContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList]
    ) {
        contentBlockingPolicy = policy
        self.balancedContentRuleLists = balancedRuleLists
        page?.applyContentBlocking(
            policy: policy,
            balancedRuleLists: balancedRuleLists
        )
    }

    func setCredentialAccessEnabled(_ isEnabled: Bool) {
        page?.setCredentialAccessEnabled(isEnabled)
    }

    func relinquishPage() -> BrowserPage? {
        guard let page else { return nil }
        isInvalidated = true
        page.stopMonitoringUserActivity()
        self.page = nil
        // The page is becoming a real tab, which announces itself. Holding the
        // transient announcement open would describe one web view twice.
        extensionPageDidChange(nil)
        return page
    }
}
