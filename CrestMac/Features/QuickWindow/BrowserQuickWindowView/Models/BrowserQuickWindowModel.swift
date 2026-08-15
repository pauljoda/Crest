import Foundation
import Observation

@Observable
@MainActor
final class BrowserQuickWindowModel {
    private(set) var presentedRequest: BrowserQuickWindowRequest
    private(set) var selectedAssignment: BrowserSpaceRuntimeAssignment
    private(set) var pageLease: BrowserTransientPageLease?
    private(set) var releasedPageSnapshot: BrowserTransientPageSnapshot?
    private(set) var wasPromoted = false
    private(set) var wasArchived = false
    let activityClock: BrowserTransientActivityClock

    @ObservationIgnored let browser: BrowserStore
    @ObservationIgnored let pages: BrowserPagePool?
    @ObservationIgnored private let spaceAccess: BrowserSpaceAccessController
    @ObservationIgnored private let supportsLivePagePromotion: Bool
    @ObservationIgnored private let preferences: BrowserTransientBrowsingPreferences
    @ObservationIgnored private let requestLifecycle: BrowserQuickWindowRequestLifecycle

    init(
        request: BrowserQuickWindowRequest,
        browser: BrowserStore,
        pages: BrowserPagePool,
        spaceAccess: BrowserSpaceAccessController,
        supportsLivePagePromotion: Bool,
        preferences: BrowserTransientBrowsingPreferences,
        requestLifecycle: BrowserQuickWindowRequestLifecycle
    ) {
        presentedRequest = request
        selectedAssignment = request.assignment
        self.browser = browser
        self.pages = pages
        self.spaceAccess = spaceAccess
        self.supportsLivePagePromotion = supportsLivePagePromotion
        self.preferences = preferences
        self.requestLifecycle = requestLifecycle
        activityClock = BrowserTransientActivityClock()
    }

    init(
        previewing request: BrowserQuickWindowRequest,
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController
    ) {
        presentedRequest = request
        selectedAssignment = request.assignment
        self.browser = browser
        pages = nil
        self.spaceAccess = spaceAccess
        supportsLivePagePromotion = false
        preferences = .isolated
        requestLifecycle = .preview
        activityClock = BrowserTransientActivityClock(
            now: Date(timeIntervalSince1970: 0)
        )
    }

    var space: BrowserSpace? {
        browser.space(matching: selectedAssignment)
    }

    var page: BrowserPage? {
        pageLease?.page
    }

    var availableSpaces: [BrowserSpace] {
        browser.session.spaces.filter {
            !browser.deletingSpaceIDs.contains($0.id)
                && ($0.id == selectedAssignment.spaceID || !spaceAccess.isLocked($0))
        }
    }

    func preparePage(isActive: Bool) {
        guard isCurrentRequest else {
            releasePageRetainingSnapshot()
            return
        }
        guard let space,
            let url = page?.url
                ?? releasedPageSnapshot?.url
                ?? presentedRequest.initialURL
        else {
            releaseUnavailableLease()
            return
        }
        guard !spaceAccess.isLocked(space) else {
            releaseForUnavailableSpace()
            return
        }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard assignment == selectedAssignment else {
            releaseUnavailableLease()
            return
        }
        if let pageLease,
            pageLease.assignment == assignment,
            pageLease.canBeReused
        {
            pageLease.setActive(isActive)
            return
        }
        pageLease?.release()
        guard let pages else { return }
        pageLease = pages.makeTransientPageLease(
            url: url,
            in: space,
            onUserActivity: recordUserActivity
        )
        if pageLease != nil {
            releasedPageSnapshot = nil
        }
        pageLease?.setActive(isActive)
    }

    func open(_ url: URL, isActive: Bool) {
        guard isCurrentRequest,
            let space,
            BrowserSpaceRuntimeAssignment(space: space)
                == selectedAssignment,
            !spaceAccess.isLocked(space)
        else { return }
        activityClock.recordActivity(restartsTimerImmediately: true)
        guard
            revisePresentedRequest(
                url: url,
                assignment: selectedAssignment
            )
        else { return }
        if let page {
            page.load(url)
            return
        }
        guard let pages else { return }
        pageLease = pages.makeTransientPageLease(
            url: url,
            in: space,
            onUserActivity: recordUserActivity
        )
        if pageLease != nil {
            releasedPageSnapshot = nil
        }
        pageLease?.setActive(isActive)
    }

    func selectSpace(_ candidate: BrowserSpace) {
        let assignment = BrowserSpaceRuntimeAssignment(space: candidate)
        guard isCurrentRequest,
            let liveCandidate = browser.space(matching: assignment),
            !spaceAccess.isLocked(liveCandidate),
            assignment != selectedAssignment
        else { return }
        activityClock.recordActivity(restartsTimerImmediately: true)
        let currentURL = currentSnapshot?.url ?? presentedRequest.initialURL
        guard
            revisePresentedRequest(
                url: currentURL ?? presentedRequest.url,
                assignment: assignment
            )
        else { return }
        pageLease?.release()
        pageLease = nil
        releasedPageSnapshot = nil
        selectedAssignment = assignment
        if let currentURL {
            preferences.rememberSpace(candidate.id, for: currentURL)
        }
    }

    @discardableResult
    func promote(to destination: BrowserSpace) -> Bool {
        activityClock.recordActivity(restartsTimerImmediately: true)
        guard isCurrentRequest, let pages else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: destination)
        guard
            assignment.spaceID != selectedAssignment.spaceID
                || assignment == selectedAssignment
        else { return false }
        guard let sourceSpace = browser.space(matching: selectedAssignment),
            !spaceAccess.isLocked(sourceSpace),
            let liveDestination = browser.space(matching: assignment),
            !spaceAccess.isLocked(liveDestination)
        else { return false }

        if let url = page?.url ?? presentedRequest.initialURL {
            guard
                let tabID = browser.openNewTab(
                    url: url,
                    matching: assignment
                ),
                let currentDestination = browser.space(
                    matching: assignment
                )
            else { return false }
            let adoptedLivePage =
                if let pageLease {
                    supportsLivePagePromotion
                        && pageLease.assignment == assignment
                        && pages.adoptTransientPage(
                            pageLease,
                            as: tabID,
                            in: currentDestination
                        )
                } else {
                    false
                }
            if assignment != selectedAssignment {
                preferences.rememberSpace(assignment.spaceID, for: url)
            }
            wasPromoted = true
            if let pageLease, !adoptedLivePage {
                pageLease.release()
            }
        } else {
            browser.selectSpace(assignment.spaceID)
            guard browser.selectedSpace?.id == assignment.spaceID else {
                return false
            }
            wasPromoted = true
        }

        pages.select(session: browser.session)
        return true
    }

    func recordCompletedNavigation() {
        guard isCurrentRequest,
            let pageLease,
            let page = pageLease.page,
            let url = page.url
        else { return }
        activityClock.recordActivity(restartsTimerImmediately: true)
        browser.recordVisit(
            url: url,
            title: page.title,
            matching: pageLease.assignment
        )
    }

    func updatePresentedURL(_ url: URL) {
        revisePresentedRequest(
            url: url,
            assignment: selectedAssignment
        )
    }

    @discardableResult
    func archivePageIfNeeded() -> Bool {
        guard !wasArchived,
            !wasPromoted,
            let snapshot = currentSnapshot
        else { return false }
        guard
            browser.archiveTransientPage(
                url: snapshot.url,
                title: snapshot.title,
                matching: snapshot.assignment
            )
        else { return false }
        wasArchived = true
        return true
    }

    func releaseForUnavailableSpace() {
        if let pageLease {
            releasedPageSnapshot = snapshot(pageLease)
        }
        pageLease?.release()
        pageLease = nil
    }

    func releaseForDismissal() {
        if !wasPromoted {
            archivePageIfNeeded()
        }
        pageLease?.release()
        pageLease = nil
        releasedPageSnapshot = nil
    }

    func restorePage() {
        activityClock.recordActivity(restartsTimerImmediately: true)
        guard isCurrentRequest else {
            releasePageRetainingSnapshot()
            return
        }
        guard let pageLease else { return }
        guard let space = browser.space(matching: pageLease.assignment) else {
            releaseUnavailableLease()
            return
        }
        guard !spaceAccess.isLocked(space) else {
            releaseForUnavailableSpace()
            return
        }
        pageLease.restore()
    }

    func setActive(_ isActive: Bool) {
        guard isCurrentRequest else {
            releasePageRetainingSnapshot()
            return
        }
        guard let space,
            !spaceAccess.isLocked(space)
        else {
            releaseForUnavailableSpace()
            return
        }
        pageLease?.setActive(isActive)
        if isActive {
            activityClock.recordActivity(restartsTimerImmediately: true)
        }
    }

    func recordUserActivity() {
        activityClock.recordActivity()
    }

    func waitUntilArchiveIsDue() async -> Bool {
        guard isCurrentRequest,
            let lifetime = preferences.archiveLifetime,
            await activityClock.waitUntilInactive(for: lifetime),
            isCurrentRequest
        else { return false }
        return true
    }

    private func releaseUnavailableLease() {
        guard let pageLease,
            browser.space(matching: pageLease.assignment) == nil
        else {
            return
        }
        pageLease.release()
        self.pageLease = nil
        releasedPageSnapshot = nil
    }

    @discardableResult
    private func revisePresentedRequest(
        url: URL,
        assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        let expected = presentedRequest
        let revised = presentedRequest.retargeted(
            to: url,
            assignment: assignment
        )
        guard
            revised.url != presentedRequest.url
                || revised.assignment != presentedRequest.assignment
        else {
            return isCurrentRequest
        }
        guard requestLifecycle.replace(expected, with: revised) else {
            releasePageRetainingSnapshot()
            return false
        }
        presentedRequest = revised
        return true
    }

    private var isCurrentRequest: Bool {
        requestLifecycle.isCurrent(presentedRequest)
    }

    private var currentSnapshot: BrowserTransientPageSnapshot? {
        pageLease.map(snapshot) ?? releasedPageSnapshot
    }

    private func snapshot(
        _ lease: BrowserTransientPageLease
    ) -> BrowserTransientPageSnapshot {
        BrowserTransientPageSnapshot(
            assignment: lease.assignment,
            url: lease.recoverableURL,
            title: lease.page?.title
        )
    }

    private func releasePageRetainingSnapshot() {
        if let pageLease {
            releasedPageSnapshot = snapshot(pageLease)
        }
        pageLease?.release()
        pageLease = nil
    }
}
