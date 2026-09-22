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

    var motionState: BrowserPeekMotionState? {
        guard case .peek(let peek) = request else { return nil }
        return coordinator.motionState(for: peek)
    }

    var isSelected: Bool {
        guard case .peek(let peek) = request else { return true }
        return peek.isSelected(in: browser.session)
    }

    var hasSource: Bool {
        guard case .peek(let peek) = request else { return space != nil }
        return peek.hasSource(in: browser.session)
    }

    var availableSpaces: [BrowserSpace] {
        BrowserTransientSessionPolicy.availableSpaces(
            in: browser.session.spaces,
            deletingSpaceIDs: browser.deletingSpaceIDs,
            requestSpaceID: request.spaceID,
            isLocked: spaceAccess.isLocked
        )
    }

    var activityRevision: Int {
        activityClock.revision
    }

    var completedNavigationCount: Int? {
        page?.completedNavigationCount
    }

    @discardableResult
    func preparePage(isActive: Bool) -> Bool {
        let space: BrowserSpace
        switch sourceDisposition {
        case .notPresented:
            releasePageRetainingQuickWindowSnapshot()
            return false
        case .sourceMissing:
            dismissUnavailableRequest()
            return false
        case .sourceLocked:
            setSourceLocked(true)
            return false
        case .usable(let usableSpace):
            space = usableSpace
        }
        if let pageLease,
            BrowserTransientSessionPolicy.reusesLease(
                leaseAssignment: pageLease.assignment,
                requestAssignment: request.spaceAssignment,
                leaseCanBeReused: pageLease.page != nil
                    || pageLease.wasReleasedForMemoryPressure
            )
        {
            pageLease.setActive(isActive && isSelected)
            return true
        }
        pageLease?.release()
        resetNavigationRecording()
        guard let pages else { return true }
        if case .peek(let peek) = request {
            pageLease = pages.makePeekPageLease(
                request: peek, in: space,
                onDownloadOnlyNavigation: { [weak coordinator] in
                    coordinator?.dismissPeek(peek)
                })
        } else {
            pageLease = pages.makeTransientPageLease(
                url: releasedPageSnapshot?.url ?? request.url,
                in: space,
                onUserActivity: recordUserActivity,
                onDownloadOnlyNavigation: { [weak self] in
                    self?.dismissDownloadOnlyNavigation()
                }
            )
        }
        guard let pageLease else {
            dismissUnavailableRequest()
            return false
        }
        releasedPageSnapshot = nil
        pageLease.setActive(isActive && isSelected)
        return true
    }

    func setActive(_ isActive: Bool) {
        switch sourceDisposition {
        case .notPresented:
            releasePageRetainingQuickWindowSnapshot()
            return
        case .sourceMissing:
            dismissUnavailableRequest()
            return
        case .sourceLocked:
            setSourceLocked(true)
            return
        case .usable:
            break
        }
        pageLease?.setActive(isActive && isSelected)
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
        switch disposition(ofSpaceMatching: pageLease.assignment) {
        case .notPresented:
            releasePageRetainingQuickWindowSnapshot()
        case .sourceMissing:
            dismissUnavailableRequest()
        case .sourceLocked:
            setSourceLocked(true)
        case .usable:
            resetNavigationRecording()
            pageLease.restore()
        }
    }

    @discardableResult
    func promote(to destinationAssignment: BrowserSpaceRuntimeAssignment) -> Bool {
        activityClock.recordActivity(restartsTimerImmediately: true)
        guard let pages,
            isCurrentRequest,
            !wasPromoted, !wasArchived,
            let pageLease,
            let page = pageLease.page,
            let outcome = BrowserTransientPagePromotion(
                requestID: request.id,
                url: page.url ?? request.url,
                sourceAssignment: request.spaceAssignment,
                leaseAssignment: pageLease.assignment,
                destinationAssignment: destinationAssignment
            ).perform(
                in: browser,
                isLocked: spaceAccess.isLocked,
                adoptPage: { tabID, destination in
                    pages.adoptTransientPage(pageLease, as: tabID, in: destination)
                }
            )
        else { return false }

        if case .quickWindow(let quickWindowRequest) = request {
            let pageURL = page.url ?? quickWindowRequest.initialURL
            if BrowserCorePolicy.quickWindowRetarget(quickWindowRequest, to: pageURL ?? quickWindowRequest.url,
                assignment: destinationAssignment, pageURL: pageURL).remembersSpace, let pageURL {
                preferences.rememberSpace(destinationAssignment.spaceID, for: pageURL)
            }
        }
        wasPromoted = true
        if outcome == .openedNewPage {
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
        if !request.isQuickWindow && isCurrentRequest {
            pageLease?.setActive(false)
        } else {
            pageLease?.release()
        }
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
        let snapshot = currentSnapshot
        guard request.isQuickWindow,
            BrowserCorePolicy.quickWindowArchivesOnDismissal(
                wasArchived: wasArchived, wasPromoted: wasPromoted, hasPage: snapshot != nil),
            let snapshot,
            browser.archiveTransientPage(
                url: snapshot.url,
                title: snapshot.title,
                matching: snapshot.assignment,
                requestID: request.id
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
        let pageURL = currentSnapshot?.url ?? quickWindowRequest.initialURL
        let currentURL = pageURL ?? quickWindowRequest.url
        let retarget = BrowserCorePolicy.quickWindowRetarget(quickWindowRequest, to: currentURL,
            assignment: destinationAssignment, pageURL: pageURL)
        guard retarget.revises else { return }
        if retarget.remembersSpace, let pageURL {
            preferences.rememberSpace(destinationAssignment.spaceID, for: pageURL)
        }
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

    private var sourceDisposition: BrowserTransientLeaseDisposition {
        disposition(ofSpaceMatching: request.spaceAssignment)
    }

    private func disposition(
        ofSpaceMatching assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserTransientLeaseDisposition {
        BrowserTransientSessionPolicy.disposition(
            isPresentingRequest: isCurrentRequest,
            space: hasSource ? browser.space(matching: assignment) : nil,
            isLocked: spaceAccess.isLocked
        )
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
