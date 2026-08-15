import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@Observable
@MainActor
final class MobileBrowserTransientPageLease {
    let id = UUID()
    let spaceID: SpaceID
    let profileID: UUID
    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }
    private(set) var page: MobileBrowserPage?
    private(set) var wasReleasedForMemoryPressure = false
    var recoverableURL: URL { page?.url ?? reloadURL }

    @ObservationIgnored private(set) var isActive = true
    @ObservationIgnored private var reloadURL: URL
    @ObservationIgnored private let rebuild: () -> MobileBrowserPage?
    @ObservationIgnored private let userActivity: () -> Void
    @ObservationIgnored private var contentBlockingPolicy: BrowserContentBlockingPolicy
    @ObservationIgnored private var balancedContentRuleLists: [WKContentRuleList]
    @ObservationIgnored private var isInvalidated = false

    init(
        page: MobileBrowserPage,
        url: URL,
        contentBlockingPolicy: BrowserContentBlockingPolicy,
        balancedContentRuleLists: [WKContentRuleList],
        rebuild: @escaping () -> MobileBrowserPage?,
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

    func relinquishPage() -> MobileBrowserPage? {
        guard let page else { return nil }
        isInvalidated = true
        page.stopMonitoringUserActivity()
        self.page = nil
        return page
    }
}
