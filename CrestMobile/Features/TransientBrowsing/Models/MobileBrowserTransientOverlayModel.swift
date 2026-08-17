import Foundation
import Observation

@Observable
@MainActor
final class MobileBrowserTransientOverlayModel {
    let request: MobileBrowserTransientRequest
    private(set) var pageLease: MobileBrowserTransientPageLease?
    private(set) var releasedPageSnapshot: BrowserTransientPageSnapshot?
    private(set) var wasPromoted = false
    private(set) var wasArchived = false
    private(set) var lastRecordedCompletedNavigationCount: Int?
    @ObservationIgnored private(set) var lastRecordedNavigationPageIdentity: ObjectIdentifier?

    @ObservationIgnored let browser: BrowserStore
    @ObservationIgnored private let pages: MobileBrowserPageStore?
    @ObservationIgnored private let coordinator: BrowserTransientBrowsingCoordinator
    @ObservationIgnored private let spaceAccess: BrowserSpaceAccessController
    @ObservationIgnored private let preferences: BrowserTransientBrowsingPreferences
    @ObservationIgnored private let activityClock: BrowserTransientActivityClock
    @ObservationIgnored private let didPromote: () -> Void

    init(
        request: MobileBrowserTransientRequest,
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        coordinator: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController,
        preferences: BrowserTransientBrowsingPreferences,
        didPromote: @escaping () -> Void = {}
    ) {
        self.request = request
        self.browser = browser
        self.pages = pages
        self.coordinator = coordinator
        self.spaceAccess = spaceAccess
        self.preferences = preferences
        self.didPromote = didPromote
        activityClock = BrowserTransientActivityClock()
    }

    init(
        previewing request: MobileBrowserTransientRequest,
        browser: BrowserStore,
        coordinator: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.request = request
        self.browser = browser
        pages = nil
        self.coordinator = coordinator
        self.spaceAccess = spaceAccess
        preferences = .isolated
        didPromote = {}
        activityClock = BrowserTransientActivityClock(
            now: Date(timeIntervalSince1970: 0)
        )
    }

    var space: BrowserSpace? {
        browser.space(matching: request.spaceAssignment)
    }

    var page: MobileBrowserPage? {
        pageLease?.page
    }

    var availableSpaces: [BrowserSpace] {
        browser.session.spaces.filter {
            !browser.deletingSpaceIDs.contains($0.id)
                && ($0.id == request.spaceID || !spaceAccess.isLocked($0))
        }
    }

    var activityRevision: Int {
        activityClock.revision
    }

    var completedNavigationCount: Int? {
        page?.completedNavigationCount
    }

    @discardableResult
    func preparePage(isActive: Bool) -> Bool {
        guard isCurrentRequest else {
            releasePageRetainingQuickWindowSnapshot()
            return false
        }
        guard let space else {
            dismissUnavailableRequest()
            return false
        }
        guard !spaceAccess.isLocked(space) else {
            setSourceLocked(true)
            return false
        }
        if let pageLease,
            pageLease.assignment == request.spaceAssignment,
            pageLease.page != nil || pageLease.wasReleasedForMemoryPressure
        {
            pageLease.setActive(isActive)
            return true
        }
        pageLease?.release()
        resetNavigationRecording()
        guard let pages else { return true }
        pageLease = pages.makeTransientPageLease(
            url: releasedPageSnapshot?.url ?? request.url,
            in: space,
            onUserActivity: recordUserActivity,
            onDownloadOnlyNavigation: { [weak self] in
                self?.dismissDownloadOnlyNavigation()
            }
        )
        guard let pageLease else {
            dismissUnavailableRequest()
            return false
        }
        releasedPageSnapshot = nil
        pageLease.setActive(isActive)
        return true
    }

    func setActive(_ isActive: Bool) {
        guard isCurrentRequest else {
            releasePageRetainingQuickWindowSnapshot()
            return
        }
        guard let space = browser.space(matching: request.spaceAssignment) else {
            dismissUnavailableRequest()
            return
        }
        guard !spaceAccess.isLocked(space) else {
            setSourceLocked(true)
            return
        }
        pageLease?.setActive(isActive)
        guard isActive else { return }
        activityClock.recordActivity(restartsTimerImmediately: true)
    }

    func setSourceLocked(_ isLocked: Bool) {
        guard isLocked else { return }
        releasePageRetainingQuickWindowSnapshot()
    }

    func setSourceAvailable(_ isAvailable: Bool) {
        guard !isAvailable else { return }
        dismissUnavailableRequest()
    }

    func recordCompletedNavigation(
        _ completedNavigationCount: Int,
        during presentationPhase: BrowserPeekPresentationPhase
    ) {
        guard presentationPhase == .committed,
            completedNavigationCount > 0,
            isCurrentRequest,
            let pageLease,
            let page = pageLease.page,
            let url = page.url
        else { return }
        let pageIdentity = ObjectIdentifier(page)
        guard
            pageIdentity != lastRecordedNavigationPageIdentity
                || completedNavigationCount != lastRecordedCompletedNavigationCount
        else { return }
        guard
            browser.recordVisit(
                url: url,
                title: page.title,
                matching: pageLease.assignment
            )
        else { return }
        lastRecordedNavigationPageIdentity = pageIdentity
        lastRecordedCompletedNavigationCount = completedNavigationCount
        activityClock.recordActivity(restartsTimerImmediately: true)
    }

    func recordUserActivity() {
        activityClock.recordActivity()
    }

    func restorePage() {
        activityClock.recordActivity(restartsTimerImmediately: true)
        guard isCurrentRequest else {
            releasePageRetainingQuickWindowSnapshot()
            return
        }
        guard let pageLease else { return }
        guard let space = browser.space(matching: pageLease.assignment) else {
            dismissUnavailableRequest()
            return
        }
        guard !spaceAccess.isLocked(space) else {
            setSourceLocked(true)
            return
        }
        resetNavigationRecording()
        pageLease.restore()
    }

    @discardableResult
    func promote(to destinationAssignment: BrowserSpaceRuntimeAssignment) -> Bool {
        activityClock.recordActivity(restartsTimerImmediately: true)
        guard let pages,
            isCurrentRequest,
            let pageLease,
            let page = pageLease.page,
            pageLease.assignment == request.spaceAssignment,
            let sourceSpace = browser.space(matching: request.spaceAssignment),
            !spaceAccess.isLocked(sourceSpace),
            let destinationSpace = browser.space(
                matching: destinationAssignment
            ),
            !spaceAccess.isLocked(destinationSpace),
            let url = page.url ?? Optional(request.url),
            let tabID = browser.openNewTab(
                url: url,
                matching: BrowserSpaceRuntimeAssignment(space: destinationSpace)
            ),
            let currentDestination = browser.space(
                matching: BrowserSpaceRuntimeAssignment(space: destinationSpace)
            )
        else { return false }

        let adoptedLivePage =
            pageLease.assignment
            == BrowserSpaceRuntimeAssignment(space: currentDestination)
            && pages.adoptTransientPage(
                pageLease,
                as: tabID,
                in: currentDestination
            )
        if request.isQuickWindow,
            destinationAssignment != request.spaceAssignment
        {
            preferences.rememberSpace(destinationAssignment.spaceID, for: url)
        }
        wasPromoted = true
        if !adoptedLivePage {
            pageLease.release()
            pages.select(session: browser.session)
        }
        dismissCoordinatorRequest()
        didPromote()
        return true
    }

    func selectLockedSpace(_ assignment: BrowserSpaceRuntimeAssignment) {
        guard isCurrentRequest else { return }
        switch request {
        case .quickWindow:
            changeQuickWindowSpace(to: assignment)
        case .peek(let peekRequest):
            guard let candidate = browser.space(matching: assignment),
                !spaceAccess.isLocked(candidate),
                coordinator.dismissPeek(peekRequest)
            else { return }
            browser.selectSpace(assignment.spaceID)
        }
    }

    func dismiss() {
        dismissCoordinatorRequest()
    }

    func dismissUnavailableRequest() {
        guard isCurrentRequest else { return }
        pageLease?.release()
        pageLease = nil
        resetNavigationRecording()
        releasedPageSnapshot = nil
        switch request {
        case .peek(let peekRequest):
            coordinator.dismissPeek(peekRequest)
        case .quickWindow(let quickWindowRequest):
            coordinator.dismissQuickWindow(quickWindowRequest)
        }
    }

    func handleDisappearance() {
        guard !wasPromoted else { return }
        archiveQuickWindowIfNeeded()
        pageLease?.release()
        pageLease = nil
        resetNavigationRecording()
        releasedPageSnapshot = nil
    }

    func autoArchiveAfterInactivity() async {
        guard request.isQuickWindow,
            isCurrentRequest,
            let lifetime = preferences.archiveLifetime,
            await activityClock.waitUntilInactive(for: lifetime)
        else { return }
        dismissCoordinatorRequest()
    }

    private func dismissCoordinatorRequest() {
        guard isCurrentRequest else { return }
        switch request {
        case .peek(let peekRequest):
            coordinator.dismissPeek(peekRequest)
        case .quickWindow(let quickWindowRequest):
            archiveQuickWindowIfNeeded()
            coordinator.dismissQuickWindow(quickWindowRequest)
        }
    }

    private func dismissDownloadOnlyNavigation() {
        guard isCurrentRequest else { return }
        releasedPageSnapshot = nil
        switch request {
        case .peek(let peekRequest):
            coordinator.dismissPeek(peekRequest)
        case .quickWindow(let quickWindowRequest):
            coordinator.dismissQuickWindow(quickWindowRequest)
        }
    }

    private func archiveQuickWindowIfNeeded() {
        guard request.isQuickWindow,
            !wasArchived,
            !wasPromoted,
            let snapshot = currentSnapshot,
            browser.archiveTransientPage(
                url: snapshot.url,
                title: snapshot.title,
                matching: snapshot.assignment
            )
        else { return }
        wasArchived = true
    }

    private func changeQuickWindowSpace(
        to destinationAssignment: BrowserSpaceRuntimeAssignment
    ) {
        guard isCurrentRequest,
            case .quickWindow(let quickWindowRequest) = request,
            destinationAssignment.spaceID != quickWindowRequest.spaceID,
            let destination = browser.space(matching: destinationAssignment),
            !spaceAccess.isLocked(destination)
        else { return }
        let currentURL = currentSnapshot?.url ?? quickWindowRequest.url
        preferences.rememberSpace(destinationAssignment.spaceID, for: currentURL)
        pageLease?.release()
        pageLease = nil
        resetNavigationRecording()
        releasedPageSnapshot = nil
        coordinator.presentQuickWindow(
            quickWindowRequest.retargeted(
                to: currentURL,
                assignment: destinationAssignment
            )
        )
    }

    private var isCurrentRequest: Bool {
        switch request {
        case .peek(let peekRequest):
            coordinator.isPresentingPeek(peekRequest)
        case .quickWindow(let quickWindowRequest):
            coordinator.isPresentingQuickWindow(quickWindowRequest)
        }
    }

    private func resetNavigationRecording() {
        lastRecordedNavigationPageIdentity = nil
        lastRecordedCompletedNavigationCount = nil
    }

    private func releasePageRetainingQuickWindowSnapshot() {
        if request.isQuickWindow, let pageLease {
            releasedPageSnapshot = snapshot(pageLease)
        }
        pageLease?.release()
        pageLease = nil
        resetNavigationRecording()
    }

    private var currentSnapshot: BrowserTransientPageSnapshot? {
        pageLease.map(snapshot) ?? releasedPageSnapshot
    }

    private func snapshot(
        _ lease: MobileBrowserTransientPageLease
    ) -> BrowserTransientPageSnapshot {
        BrowserTransientPageSnapshot(
            assignment: lease.assignment,
            url: lease.recoverableURL,
            title: lease.page?.title
        )
    }
}
