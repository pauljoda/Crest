import Foundation
import Observation
import WebKit

@Observable
@MainActor
final class BrowserTransientPageLease {
    let id = UUID()
    /// The Space and profile that own this transient page.
    let spaceID: SpaceID
    let profileID: UUID
    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }
    private(set) var page: BrowserPlatformPage?
    /// The core page the lease last held, which stays named after memory
    /// pressure takes the page back.
    private(set) var pageID: UUID
    private(set) var wasReleasedForMemoryPressure = false
    var recoverableURL: URL { page?.live.documentURL ?? reloadURL }
    var canBeReused: Bool { page != nil || wasReleasedForMemoryPressure }

    @ObservationIgnored private(set) var isActive = true
    @ObservationIgnored private var reloadURL: URL
    @ObservationIgnored private let rebuild: () -> BrowserPlatformPage?
    @ObservationIgnored private let userActivity: () -> Void
    @ObservationIgnored private let onDownloadOnlyNavigation: (() -> Void)?
    @ObservationIgnored private var contentBlockingPolicy: ContentBlockingPolicy
    @ObservationIgnored private var balancedContentRuleLists: [WKContentRuleList]
    @ObservationIgnored private var isInvalidated = false
    /// The core page memory pressure unloaded, which the core remembers until
    /// the lease brings the page back or lets it go and releases it for good.
    @ObservationIgnored private var unloaded: CorePage?

    init(
        page: BrowserPlatformPage,
        url: URL,
        contentBlockingPolicy: ContentBlockingPolicy,
        balancedContentRuleLists: [WKContentRuleList],
        rebuild: @escaping () -> BrowserPlatformPage?,
        userActivity: @escaping () -> Void,
        onDownloadOnlyNavigation: (() -> Void)? = nil
    ) {
        self.page = page
        pageID = page.corePage.id
        spaceID = page.spaceID
        profileID = page.profileID
        reloadURL = url
        self.contentBlockingPolicy = contentBlockingPolicy
        self.balancedContentRuleLists = balancedContentRuleLists
        self.rebuild = rebuild
        self.userActivity = userActivity
        self.onDownloadOnlyNavigation = onDownloadOnlyNavigation
        page.monitorUserActivity(userActivity)
        page.corePage.navigate(to: url.absoluteString)
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
        page.corePage.navigate(to: reloadURL.absoluteString)
        self.page = page
        pageID = page.corePage.id
        wasReleasedForMemoryPressure = false
        unloaded?.release(keepingState: false)
        unloaded = nil
    }

    /// Unloads the page, keeping what the lease needs to bring it back, so the
    /// core still knows what it showed when its window keeps or archives it.
    func releaseForMemoryPressure() {
        guard let page else { return }
        reloadURL = page.live.documentURL ?? reloadURL
        unloaded = page.corePage
        page.release(keepingState: true)
        self.page = nil
        wasReleasedForMemoryPressure = true
    }

    func release() {
        isInvalidated = true
        page?.release(keepingState: false)
        page = nil
        unloaded?.release(keepingState: false)
        unloaded = nil
    }

    /// Lets the page go for good as far as this lease goes, but unloads it
    /// with its state kept, so the core still knows what it showed, and hands
    /// its owner the core page to release for good once nothing will keep or
    /// archive it.
    func unload() -> CorePage? {
        isInvalidated = true
        if let page {
            unloaded = page.corePage
            page.release(keepingState: true)
            self.page = nil
        }
        defer { unloaded = nil }
        return unloaded
    }

    @discardableResult
    func discardForDownloadOnlyNavigation() -> Bool {
        guard !isInvalidated, let onDownloadOnlyNavigation else { return false }
        release()
        onDownloadOnlyNavigation()
        return true
    }

    func applyContentBlocking(
        policy: ContentBlockingPolicy,
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

    func relinquishPage() -> BrowserPlatformPage? {
        guard let page else { return nil }
        isInvalidated = true
        page.stopMonitoringUserActivity()
        self.page = nil
        return page
    }
}
