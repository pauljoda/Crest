import Dispatch
import Foundation
import Observation
import WebKit
import os

@Observable
@MainActor
final class BrowserTransientPageLease {
    let id = UUID()
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
    @ObservationIgnored private var contentBlockingPolicy: BrowserContentBlockingPolicy
    @ObservationIgnored private var balancedContentRuleLists: [WKContentRuleList]
    @ObservationIgnored private var isInvalidated = false

    init(
        page: BrowserPage,
        url: URL,
        contentBlockingPolicy: BrowserContentBlockingPolicy,
        balancedContentRuleLists: [WKContentRuleList],
        rebuild: @escaping () -> BrowserPage?,
        userActivity: @escaping () -> Void
    ) {
        self.page = page
        spaceID = page.spaceID
        profileID = page.profileID
        reloadURL = url
        self.contentBlockingPolicy = contentBlockingPolicy
        self.balancedContentRuleLists = balancedContentRuleLists
        self.rebuild = rebuild
        self.userActivity = userActivity
        page.monitorUserActivity(userActivity)
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
    }

    func release() {
        isInvalidated = true
        page?.prepareForSpaceDeletion()
        page = nil
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
        return page
    }
}
